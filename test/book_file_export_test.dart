import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';
import 'package:wenku8_flutter/book_file_export.dart';
import 'package:wenku8_flutter/catalog.dart';
import 'package:wenku8_flutter/local_books.dart';
import 'package:wenku8_flutter/offline_cache.dart';
import 'package:wenku8_flutter/offline_repository.dart';

const exportBook = Novel(
  id: 752,
  title: '书页与微光 & <故事>',
  author: '作者',
  genre: '奇幻 冒险',
  summary: '一本用于文件格式回归的书。',
  colors: [Colors.grey, Colors.black],
  coverUrl: 'https://cover.wenku8.com/752.jpg',
  chapters: [
    NovelChapter(
      '序章',
      '正文 <标记> & "句子"。🙂\n\n<!--image-->https://pic.wenku8.com/a.png<!--image-->',
      id: 1,
      volumeId: 1,
      volumeTitle: '第一卷',
    ),
    NovelChapter(
      '下一章',
      '第二段正文。\n\n<!--image-->https://pic.wenku8.com/a.png<!--image-->',
      id: 2,
      volumeId: 1,
      volumeTitle: '第一卷',
    ),
    NovelChapter('第二卷 第一章', '最后一段。', id: 3, volumeId: 2, volumeTitle: '第二卷'),
  ],
);

class ExportRepository extends DemoNovelRepository {
  final calls = <int>[];
  @override
  Future<String> chapterContent(int id, NovelChapter chapter) async {
    calls.add(chapter.id);
    return chapter.content;
  }
}

Future<Uint8List> exportPicture() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    const Rect.fromLTWH(0, 0, 40, 60),
    Paint()..color = Colors.blueGrey,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(40, 60);
  final bytes = (await image.toByteData(
    format: ui.ImageByteFormat.png,
  ))!.buffer.asUint8List();
  image.dispose();
  picture.dispose();
  return bytes;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  setUp(
    () async =>
        root = await Directory.systemTemp.createTemp('wenku-export-test-'),
  );
  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });
  test(
    'EPUB stores mimetype first, valid XML, complete volume TOC and deduplicated images',
    () async {
      final image = await exportPicture();
      final repo = ExportRepository(), images = <String>[];
      final exporter = BookFileExporter(
        repository: repo,
        directory: root,
        coverRequest: (_) async => image,
        imageRequest: (url) async {
          images.add(url);
          return image;
        },
      );
      final generated = await exporter.create(
        exportBook,
        format: BookFileFormat.epub,
        cancellation: BookExportCancellation(),
      );
      final bytes = await generated.file.readAsBytes();
      final header = ByteData.sublistView(bytes);
      expect(header.getUint16(8, Endian.little), 0);
      expect(header.getUint16(28, Endian.little), 0);
      final archive = ZipDecoder().decodeBytes(bytes);
      expect(archive.first.name, 'mimetype');
      expect(utf8.decode(archive.first.content), 'application/epub+zip');
      for (final file in archive.where(
        (f) =>
            f.name.endsWith('.xhtml') ||
            f.name.endsWith('.xml') ||
            f.name.endsWith('.opf'),
      )) {
        expect(
          () => XmlDocument.parse(utf8.decode(file.content)),
          returnsNormally,
        );
      }
      String text(String name) =>
          utf8.decode(archive.findFile('EPUB/$name')!.content);
      final package = XmlDocument.parse(text('package.opf'));
      for (final item in package.findAllElements('item')) {
        expect(
          archive.findFile('EPUB/${item.getAttribute('href')}'),
          isNotNull,
        );
      }
      final nav = XmlDocument.parse(text('nav.xhtml'));
      expect(
        nav.findAllElements('a').map((e) => e.innerText),
        exportBook.chapters.map((c) => c.title),
      );
      expect(nav.findAllElements('span').map((e) => e.innerText), [
        '第一卷',
        '第二卷',
      ]);
      expect(
        text('chapter-0.xhtml'),
        contains('正文 &lt;标记&gt; &amp; &quot;句子&quot;。🙂'),
      );
      expect(text('chapter-0.xhtml'), isNot(contains('https://pic.')));
      expect(archive.where((f) => f.name.startsWith('EPUB/images/')).length, 2);
      expect(images, ['https://pic.wenku8.com/a.png']);
      expect(repo.calls, [1, 2, 3]);
      final imported = parseLocalBook(LocalBookInput(generated.name, bytes));
      expect(imported.novel.title, exportBook.title);
      expect(imported.novel.author, exportBook.author);
      expect(imported.bodies.any((b) => b.contains('正文 <标记> & "句子"。🙂')), true);
      expect(imported.images.length, greaterThanOrEqualTo(2));
      const artifacts = String.fromEnvironment('EXPORT_ARTIFACTS');
      if (artifacts.isNotEmpty) {
        await Directory(artifacts).create(recursive: true);
        await generated.file.copy('$artifacts/validation.epub');
      }
      await generated.dispose();
      expect(await root.list().toList(), isEmpty);
    },
  );
  test(
    'TXT keeps both volume headings and source text without image markers',
    () async {
      final exporter = BookFileExporter(
        repository: ExportRepository(),
        directory: root,
        imageRequest: (_) async =>
            throw StateError('TXT must not request images'),
      );
      final file = await exporter.create(
        exportBook,
        format: BookFileFormat.txt,
        cancellation: BookExportCancellation(),
      );
      final text = await file.file.readAsString();
      expect(text, contains('正文 <标记> & "句子"。🙂'));
      expect('第一卷'.allMatches(text).length, 1);
      expect('第二卷\n'.allMatches(text).length, 1);
      expect(text, isNot(contains('<!--image-->')));
      expect(text, isNot(contains('https://')));
      expect(file.name.endsWith('.txt'), true);
      expect(file.name, isNot(contains('<')));
    },
  );
  test(
    'cancelling stops later chapter requests and removes incomplete output',
    () async {
      final repository = ExportRepository(), ticket = BookExportCancellation();
      await expectLater(
        BookFileExporter(repository: repository, directory: root).create(
          exportBook,
          format: BookFileFormat.txt,
          cancellation: ticket,
          onProgress: (p) {
            if (p.completed == 1) ticket.cancel();
          },
        ),
        throwsA(isA<BookExportCancelled>()),
      );
      expect(repository.calls, [1]);
      expect(await root.list().toList(), isEmpty);
    },
  );
  test(
    'an image failure cannot silently publish a partial illustrated EPUB',
    () async {
      final image = await exportPicture();
      await expectLater(
        BookFileExporter(
          repository: ExportRepository(),
          directory: root,
          coverRequest: (_) async => image,
          imageRequest: (_) async => throw const FormatException('插图下载失败'),
        ).create(
          exportBook,
          format: BookFileFormat.epub,
          cancellation: BookExportCancellation(),
        ),
        throwsFormatException,
      );
      expect(await root.list().toList(), isEmpty);
      final plain =
          await BookFileExporter(
            repository: ExportRepository(),
            directory: root,
          ).create(
            exportBook,
            format: BookFileFormat.epub,
            includeImages: false,
            cancellation: BookExportCancellation(),
          );
      expect(
        ZipDecoder()
            .decodeBytes(await plain.file.readAsBytes())
            .where((f) => f.name.contains('/images/')),
        isEmpty,
      );
    },
  );
  test(
    'exporting a single volume cannot replace the full cached directory',
    () async {
      final cache = OfflineCacheStore(Directory('${root.path}/cache'));
      await cache.load();
      await cache.saveBook(exportBook, epoch: cache.epochFor(exportBook.id));
      final repository = OfflineNovelRepository(
        remote: ExportRepository(),
        cache: cache,
      );
      addTearDown(repository.dispose);
      addTearDown(cache.dispose);
      await repository.find(exportBook.id);
      final scoped = exportBook.withChapters([exportBook.chapters.last]);
      await BookFileExporter(
        repository: repository,
        directory: Directory('${root.path}/exports'),
      ).create(
        scoped,
        format: BookFileFormat.txt,
        cancellation: BookExportCancellation(),
      );
      expect((await cache.readBook(exportBook.id))!.chapters.length, 3);
    },
  );
}
