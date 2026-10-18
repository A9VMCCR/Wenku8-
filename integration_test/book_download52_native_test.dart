import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wenku8_flutter/book_documents.dart';
import 'package:wenku8_flutter/book_file_export.dart';
import 'package:wenku8_flutter/catalog.dart';

class _Source extends DemoNovelRepository {
  @override
  Future<String> chapterContent(int id, NovelChapter chapter) async =>
      chapter.content;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native book save validates paths, saves a generated EPUB and handles picker cancellation',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(child: Text('Book export integration fixture')),
          ),
        ),
      );
      final documents = BookDocuments();
      final temp = await getTemporaryDirectory();
      final outside = File('${temp.path}/wenku52-outside-fixture.txt');
      await outside.writeAsString('fixture');
      try {
        await expectLater(
          documents.saveBookFile(outside, 'outside.txt'),
          throwsA(isA<PlatformException>()),
        );
      } finally {
        await outside.delete();
      }
      const book = Novel(
        id: 52400,
        title: 'Native export fixture',
        author: 'Fixture',
        genre: '',
        summary: '',
        colors: [Colors.grey, Colors.black],
        chapters: [
          NovelChapter('Chapter one', 'Native save round-trip fixture.', id: 1),
        ],
      );
      final generated = await BookFileExporter(repository: _Source()).create(
        book,
        format: BookFileFormat.epub,
        includeImages: false,
        cancellation: BookExportCancellation(),
      );
      try {
        debugPrint('READER52_NATIVE_PICKER_SAVE_READY');
        final saved = await documents.saveBookFile(
          generated.file,
          'Wenku52-export-fixture.epub',
        );
        expect(saved, isNotNull);
        expect(saved!.size, await generated.file.length());
        expect(saved.name, contains('Wenku52-export-fixture'));
        debugPrint('READER52_NATIVE_SAVED size=${saved.size}');
        debugPrint('READER52_NATIVE_PICKER_CANCEL_READY');
        final cancelled = await documents.saveBookFile(
          generated.file,
          'Wenku52-cancel-fixture.epub',
        );
        expect(cancelled, isNull);
        debugPrint(
          'READER52_NATIVE_CANCELLED path_policy=ok save=ok cancel=ok',
        );
      } finally {
        await generated.dispose();
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
