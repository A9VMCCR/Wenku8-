import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'catalog.dart';
import 'legacy_cover.dart';
import 'local_books.dart' show isLocalBook;
import 'local_book_media.dart';
import 'reader_content.dart';
import 'reader_illustrations.dart';

enum BookFileFormat { epub, txt }

class BookExportCancelled implements Exception {}

class BookExportCancellation {
  bool _cancelled = false;
  final _listeners = <VoidCallback>{};
  bool get cancelled => _cancelled;
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final listener in _listeners.toList()) {
      listener();
    }
  }

  VoidCallback listen(VoidCallback listener) {
    _listeners.add(listener);
    if (_cancelled) listener();
    return () => _listeners.remove(listener);
  }

  void check() {
    if (cancelled) throw BookExportCancelled();
  }
}

typedef BookFileProgress = ({String label, int completed, int total});

class GeneratedBookFile {
  const GeneratedBookFile(this.file, this.name, this.directory);
  final File file;
  final String name;
  final Directory directory;
  Future<void> dispose() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}

List<String> _chapterImages(String text) => text
    .split('\n\n')
    .map(readerIllustrationUrl)
    .whereType<String>()
    .toSet()
    .toList();
String _xml(String text) => text
    .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');
String _html(String title, String body, String language) =>
    '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="$language" lang="$language"><head><title>${_xml(title)}</title><link rel="stylesheet" type="text/css" href="style.css"/></head><body>$body</body></html>''';

typedef _ChapterWrite = ({
  String path,
  String title,
  String text,
  bool plain,
  String language,
  Map<String, String> images,
  bool includeImages,
  String volume,
});
int _writeChapter(_ChapterWrite input) {
  final paragraphs = input.text.split('\n\n');
  final body = StringBuffer();
  if (input.plain) {
    if (input.volume.isNotEmpty) body.writeln('\n${input.volume}\n');
    body.writeln('${input.title}\n');
    for (final paragraph in paragraphs) {
      if (readerIllustrationUrl(paragraph) == null) {
        body.writeln('$paragraph\n');
      }
    }
  } else {
    body.write('<h1>${_xml(input.title)}</h1>');
    for (final paragraph in paragraphs) {
      final image = readerIllustrationUrl(paragraph);
      if (image != null) {
        final href = input.images[image];
        if (input.includeImages && href != null) {
          body.write('<figure><img src="${_xml(href)}" alt="插图"/></figure>');
        }
      } else if (paragraph.trim().isNotEmpty) {
        body.write('<p>${paragraph.split('\n').map(_xml).join('<br/>')}</p>');
      }
    }
  }
  final value = input.plain
      ? body.toString()
      : _html(input.title, body.toString(), input.language);
  final bytes = utf8.encode(value);
  File(input.path).writeAsBytesSync(
    bytes,
    mode: input.plain ? FileMode.append : FileMode.write,
  );
  return bytes.length;
}

typedef _ImageInfo = ({String href, String media});
_ImageInfo _imageInfo(Uint8List bytes, int index) {
  String extension, media;
  if (bytes.length >= 8 &&
      bytes[0] == 137 &&
      bytes[1] == 80 &&
      bytes[2] == 78 &&
      bytes[3] == 71) {
    extension = 'png';
    media = 'image/png';
  } else if (bytes.length >= 3 &&
      bytes[0] == 255 &&
      bytes[1] == 216 &&
      bytes[2] == 255) {
    extension = 'jpg';
    media = 'image/jpeg';
  } else if (bytes.length >= 6 &&
      ascii.decode(bytes.sublist(0, 3), allowInvalid: true) == 'GIF') {
    extension = 'gif';
    media = 'image/gif';
  } else if (bytes.length >= 12 &&
      ascii.decode(bytes.sublist(0, 4), allowInvalid: true) == 'RIFF' &&
      ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WEBP') {
    extension = 'webp';
    media = 'image/webp';
  } else {
    throw const FormatException('图片格式暂不支持导出，可关闭封面与插图后重试');
  }
  return (href: 'images/image-$index.$extension', media: media);
}

Future<void> _validateImage(Uint8List bytes) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  try {
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    try {
      if (descriptor.width <= 0 || descriptor.height <= 0) {
        throw const FormatException('图片数据不完整，请重试');
      }
    } finally {
      descriptor.dispose();
    }
  } finally {
    buffer.dispose();
  }
}

String _toc(Novel book) {
  final items = StringBuffer();
  for (final volume in NovelVolume.of(book.chapters)) {
    if (volume.title.isNotEmpty) {
      items.write('<li><span>${_xml(volume.title)}</span><ol>');
    }
    for (var index = volume.start; index < volume.end; index++) {
      items.write(
        '<li><a href="chapter-$index.xhtml">${_xml(book.chapters[index].title)}</a></li>',
      );
    }
    if (volume.title.isNotEmpty) items.write('</ol></li>');
  }
  return items.toString();
}

void _packageEpub(({String root, String target, String cancel}) input) {
  final root = Directory(input.root);
  final output = OutputFileStream(input.target);
  final encoder = ZipEncoder();
  encoder.startEncode(output, level: 6);
  try {
    encoder.add(
      ArchiveFile.string('mimetype', 'application/epub+zip')
        ..compression = CompressionType.none,
    );
    final files =
        root
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    for (final file in files) {
      if (File(input.cancel).existsSync()) throw BookExportCancelled();
      final name = file.path
          .substring(root.path.length + 1)
          .replaceAll('\\', '/');
      final stream = InputFileStream(file.path);
      try {
        encoder.add(
          ArchiveFile.stream(name, stream)
            ..compression = name.startsWith('EPUB/images/')
                ? CompressionType.none
                : CompressionType.deflate,
        );
      } finally {
        stream.closeSync();
      }
      if (output.length > 512 * 1024 * 1024) {
        throw const FormatException('EPUB 超过 512 MiB，请选择单卷或关闭插图');
      }
    }
    encoder.endEncode();
  } finally {
    output.closeSync();
  }
}

/// One chapter and image at a time; no full-book body/image buffer. Compression
/// runs off the UI isolate, and a cancelled operation never opens the save UI.
class BookFileExporter {
  BookFileExporter({
    required this.repository,
    this.directory,
    this.imageRequest,
    this.coverRequest,
  });
  final NovelRepository repository;
  final Directory? directory;
  final IllustrationRequest? imageRequest;
  final Future<Uint8List> Function(Novel)? coverRequest;
  Future<GeneratedBookFile> create(
    Novel book, {
    required BookFileFormat format,
    required BookExportCancellation cancellation,
    bool includeImages = true,
    String? title,
    ValueChanged<BookFileProgress>? onProgress,
  }) async {
    final base =
        directory ??
        Directory('${(await getTemporaryDirectory()).path}/book-exports');
    await base.create(recursive: true);
    final job = await base.createTemp('download-');
    final root = Directory('${job.path}/content');
    final epub = Directory('${root.path}/EPUB');
    final output = File('${job.path}/book.${format.name}');
    var generated = false;
    try {
      cancellation.check();
      if (book.chapters.isEmpty) throw const FormatException('本书暂无可下载的章节');
      final displayTitle = title ?? book.title;
      final language = isLocalBook(book.id) ? 'und' : 'zh';
      var bytesWritten = 0;
      final images = <String, _ImageInfo>{};
      String? cover;
      void report(String label, int completed) => onProgress?.call((
        label: label,
        completed: completed,
        total: book.chapters.length,
      ));
      void checkSize(int length) {
        bytesWritten += length;
        if (bytesWritten >
            (format == BookFileFormat.txt ? 128 : 1024) * 1024 * 1024) {
          throw FormatException(
            format == BookFileFormat.txt
                ? 'TXT 超过 128 MiB，请选择单卷下载'
                : '书籍资源超过 1 GiB，请选择单卷或关闭插图',
          );
        }
      }

      if (format == BookFileFormat.epub) {
        await Directory('${epub.path}/images').create(recursive: true);
      } else {
        await output.writeAsString('$displayTitle\n${book.author}\n\n');
      }
      Future<_ImageInfo> stageImage(String url, {bool isCover = false}) async {
        if (images[url] case final existing?) return existing;
        cancellation.check();
        final bytes = isCover
            ? await (coverRequest?.call(book) ??
                  (url.startsWith('wenku-local:')
                      ? LocalBookMedia.loadCover(url)
                      : LegacyCover.bytes(book.id)))
            : await (imageRequest?.call(url) ??
                  ReaderIllustrationCache.shared.load(url));
        cancellation.check();
        if (bytes.isEmpty || bytes.length > 8 * 1024 * 1024) {
          throw const FormatException('图片大小无效，请关闭插图后重试');
        }
        final info = _imageInfo(bytes, images.length);
        await _validateImage(bytes);
        checkSize(bytes.length);
        await File('${epub.path}/${info.href}').writeAsBytes(bytes);
        images[url] = info;
        return info;
      }

      if (format == BookFileFormat.epub &&
          includeImages &&
          book.coverUrl != null) {
        report('正在准备封面', 0);
        cover = (await stageImage(book.coverUrl!, isCover: true)).href;
      }
      String? lastVolume;
      for (var index = 0; index < book.chapters.length; index++) {
        cancellation.check();
        final chapter = book.chapters[index];
        report('正在下载 · ${chapter.title}', index);
        final text = await repository.chapterContent(book.id, chapter);
        cancellation.check();
        if (text.trim().isEmpty) {
          throw FormatException('「${chapter.title}」正文为空，请重试');
        }
        final resources = <String, String>{};
        if (format == BookFileFormat.epub && includeImages) {
          final urls = text.length > 65536
              ? await compute(_chapterImages, text)
              : _chapterImages(text);
          for (final url in urls) {
            report('正在下载插图 · ${chapter.title}', index);
            resources[url] = (await stageImage(url)).href;
          }
        }
        cancellation.check();
        final volume = chapter.volumeTitle != lastVolume
            ? chapter.volumeTitle
            : '';
        lastVolume = chapter.volumeTitle;
        checkSize(
          await compute(_writeChapter, (
            path: format == BookFileFormat.txt
                ? output.path
                : '${epub.path}/chapter-$index.xhtml',
            title: chapter.title,
            text: text,
            plain: format == BookFileFormat.txt,
            language: language,
            images: resources,
            includeImages: includeImages,
            volume: volume,
          )),
        );
        report('已准备 ${index + 1} / ${book.chapters.length} 章', index + 1);
      }
      if (format == BookFileFormat.epub) {
        report('正在生成 EPUB', book.chapters.length);
        await Directory('${root.path}/META-INF').create(recursive: true);
        await File('${root.path}/META-INF/container.xml').writeAsString(
          '<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="EPUB/package.opf" media-type="application/oebps-package+xml"/></rootfiles></container>',
        );
        await File('${epub.path}/style.css').writeAsString(
          'body{margin:5%;line-height:1.8}h1{font-size:1.4em}p{text-indent:2em;white-space:pre-wrap}figure{margin:1em 0;text-align:center}img{max-width:100%;height:auto}nav ol{list-style:none;padding-left:1em}.cover{text-align:center}.cover img{max-height:80vh}',
        );
        await File('${epub.path}/front.xhtml').writeAsString(
          _html(
            displayTitle,
            '${cover == null ? '' : '<div class="cover"><img src="$cover" alt="${_xml(displayTitle)}"/></div>'}<h1>${_xml(displayTitle)}</h1><p>${_xml(book.author)}</p><p>${_xml(book.summary)}</p>',
            language,
          ),
        );
        await File('${epub.path}/nav.xhtml').writeAsString(
          _html(
            '目录',
            '<nav epub:type="toc" id="toc"><h1>目录</h1><ol>${_toc(book)}</ol></nav>',
            language,
          ),
        );
        final modified =
            '${DateTime.now().toUtc().toIso8601String().split('.').first}Z';
        final manifest = StringBuffer(
          '<item id="front" href="front.xhtml" media-type="application/xhtml+xml"/><item id="nav" href="nav.xhtml" properties="nav" media-type="application/xhtml+xml"/><item id="style" href="style.css" media-type="text/css"/>',
        );
        for (final (index, image) in images.values.indexed) {
          manifest.write(
            '<item id="image-$index" href="${image.href}" media-type="${image.media}"${image.href == cover ? ' properties="cover-image"' : ''}/>',
          );
        }
        for (var i = 0; i < book.chapters.length; i++) {
          manifest.write(
            '<item id="c$i" href="chapter-$i.xhtml" media-type="application/xhtml+xml"/>',
          );
        }
        await File('${epub.path}/package.opf').writeAsString(
          '''<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="book-id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="book-id">urn:wenku8:book:${book.id}:${book.chapters.first.id}-${book.chapters.last.id}</dc:identifier><dc:title>${_xml(displayTitle)}</dc:title><dc:creator>${_xml(book.author.isEmpty ? '佚名' : book.author)}</dc:creator><dc:language>$language</dc:language>${book.summary.trim().isEmpty ? '' : '<dc:description>${_xml(book.summary)}</dc:description>'}${book.tags.map((tag) => '<dc:subject>${_xml(tag)}</dc:subject>').join()}<meta property="dcterms:modified">$modified</meta></metadata><manifest>$manifest</manifest><spine><itemref idref="front"/>${List.generate(book.chapters.length, (i) => '<itemref idref="c$i"/>').join()}</spine></package>''',
        );
        cancellation.check();
        final cancel = File('${job.path}/cancel');
        // A cancellation marker is only used while the background packer owns
        // the ZIP. It is not a shared book/cache or a user-owned source file.
        final stopWatch = cancellation.listen(
          () => cancel.writeAsStringSync('cancel'),
        );
        try {
          await compute(_packageEpub, (
            root: root.path,
            target: '${output.path}.part',
            cancel: cancel.path,
          ));
        } finally {
          stopWatch();
        }
        cancellation.check();
        await File('${output.path}.part').rename(output.path);
      }
      cancellation.check();
      final limitMiB = format == BookFileFormat.epub ? 512 : 128;
      if (await output.length() > limitMiB * 1024 * 1024) {
        throw FormatException(
          '${format.name.toUpperCase()} 超过 $limitMiB MiB，请选择单卷下载',
        );
      }
      final name = String.fromCharCodes(
        displayTitle
            .replaceAll(RegExp(r'[/\\:*?"<>|\x00-\x1F]'), '_')
            .trim()
            .runes
            .take(90),
      );
      generated = true;
      return GeneratedBookFile(
        output,
        '${name.isEmpty ? '文库书籍' : name}.${format.name}',
        job,
      );
    } finally {
      if (!generated && await job.exists()) {
        await job.delete(recursive: true);
      }
    }
  }
}
