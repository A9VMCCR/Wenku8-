import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_ui.dart';
import 'app_interactions.dart';
import 'book_documents.dart';
import 'book_file_export.dart';
import 'catalog.dart';
import 'feature_pages.dart' show ArchiveFeaturePage;
import 'glass_choices.dart';
import 'local_books.dart' show isLocalBook;
import 'setting_menu.dart';
import 'offline_repository.dart';

class BookDownloadPage extends StatefulWidget {
  const BookDownloadPage({
    super.key,
    required this.book,
    required this.repository,
    required this.reduceMotion,
    this.documents,
    this.exporter,
  });
  final Novel book;
  final NovelRepository repository;
  final bool reduceMotion;
  final BookDocuments? documents;
  final BookFileExporter? exporter;
  @override
  State<BookDownloadPage> createState() => _BookDownloadPageState();
}

class _BookDownloadPageState extends State<BookDownloadPage> {
  BookFileFormat format = BookFileFormat.epub;
  bool includeImages = true, busy = false, saving = false, changing = false;
  String range = 'all';
  String? error, savedName;
  GeneratedBookFile? generated;
  BookExportCancellation? cancellation;
  final progress = ValueNotifier<BookFileProgress?>(null);
  late final exporter =
      widget.exporter ?? BookFileExporter(repository: widget.repository);
  late final documents = widget.documents ?? BookDocuments();
  late final volumes = NovelVolume.of(
    widget.book.chapters,
  ).where((v) => v.title.isNotEmpty).toList();
  bool get locked => busy || changing;

  Future<void> _change(VoidCallback action) async {
    if (locked) return;
    setState(() => changing = true);
    try {
      await generated?.dispose();
      generated = null;
      progress.value = null;
      if (mounted) {
        setState(() {
          action();
          error = null;
          savedName = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => error = '临时文件清理未完成，请重试');
    } finally {
      if (mounted) setState(() => changing = false);
    }
  }

  Future<void> _download() async {
    if (locked) return;
    final ticket = BookExportCancellation();
    cancellation = ticket;
    setState(() {
      busy = true;
      error = null;
      savedName = null;
    });
    GeneratedBookFile? file = generated;
    try {
      if (widget.repository case final OfflineNovelRepository offline) {
        await offline.rememberDirectory(widget.book);
      }
      final volume = volumes.where((v) => v.key == range).firstOrNull;
      final book = volume == null
          ? widget.book
          : widget.book.withChapters(
              widget.book.chapters.sublist(volume.start, volume.end),
            );
      file ??= await exporter.create(
        book,
        format: format,
        includeImages: includeImages,
        cancellation: ticket,
        title: volume == null ? null : '${book.title} · ${volume.title}',
        onProgress: (value) {
          if (mounted) progress.value = value;
        },
      );
      ticket.check();
      if (!mounted) return;
      generated = file;
      setState(() => saving = true);
      final result = await documents.saveBookFile(file.file, file.name);
      if (!mounted) return;
      if (result != null) {
        setState(() => savedName = result.name);
        showNovelFeedback(context, '书籍已保存');
      }
    } on BookExportCancelled {
      if (mounted) progress.value = null;
    } catch (failure) {
      if (mounted) {
        setState(
          () => error = switch (failure) {
            FormatException() => failure.message,
            PlatformException() => failure.message ?? '文件未保存，请重新选择位置',
            _ => '下载未完成，请检查网络与可用空间后重试',
          },
        );
      }
    } finally {
      if (!mounted) {
        await file?.dispose();
      } else {
        setState(() {
          busy = false;
          saving = false;
        });
      }
    }
  }

  @override
  void dispose() {
    cancellation?.cancel();
    if (!busy) {
      unawaited(
        generated?.dispose().catchError((Object _) {}) ?? Future<void>.value(),
      );
    }
    progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ArchiveFeaturePage(
    title: isLocalBook(widget.book.id) ? '导出书籍' : '下载书籍',
    code: 'BOOK / DOWNLOAD',
    child: ListView(
      padding: EdgeInsets.fromLTRB(
        24,
        MediaQuery.paddingOf(context).top + FrostedHeader.toolbarHeight + 20,
        24,
        MediaQuery.paddingOf(context).bottom + 32,
      ),
      children: [
        AppText(
          widget.book.title,
          style: const TextStyle(
            fontSize: 20,
            height: 1.6,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        AppText(
          '${widget.book.author} · ${widget.book.chapters.length} 章',
          style: const TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 24),
        ContentPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GlassChoiceGroup<BookFileFormat>(
                name: 'book-file-format',
                enabled: !locked,
                label: '文件格式',
                value: format,
                options: const {
                  BookFileFormat.epub: 'EPUB',
                  BookFileFormat.txt: 'TXT',
                },
                onChanged: (value) {
                  if (!locked) _change(() => format = value);
                },
              ),
              const SizedBox(height: 8),
              AppText(
                format == BookFileFormat.epub
                    ? '保留封面、分卷目录与插图，可在其他阅读器中打开。'
                    : 'UTF-8 纯文本，保留卷名与章名。',
                style: const TextStyle(fontSize: 12, height: 1.6),
              ),
              AnimatedOptionSection(
                expanded: format == BookFileFormat.epub,
                child: Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Row(
                    children: [
                      const Expanded(
                        child: AppText(
                          '包含封面与插图',
                          style: TextStyle(fontSize: 14),
                        ),
                      ),
                      const SizedBox(width: 12),
                      AppControls.toggle(
                        context,
                        key: const ValueKey('book-download-images'),
                        value: includeImages,
                        onChanged: locked
                            ? null
                            : (value) => _change(() => includeImages = value),
                      ),
                    ],
                  ),
                ),
              ),
              if (volumes.length > 1) ...[
                const SizedBox(height: 20),
                IgnorePointer(
                  ignoring: locked,
                  child: GlassSettingMenu<String>(
                    key: const ValueKey('book-download-range'),
                    icon: CupertinoIcons.book,
                    label: '下载范围',
                    value: range,
                    options: {
                      'all': '整本书',
                      for (final volume in volumes) volume.key: volume.title,
                    },
                    reduceMotion: widget.reduceMotion,
                    onChanged: (value) => _change(() => range = value),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
        ValueListenableBuilder<BookFileProgress?>(
          valueListenable: progress,
          builder: (context, value, _) => AnimatedOptionSection(
            expanded: value != null,
            child: ContentPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppText(
                    saving
                        ? '请选择保存位置'
                        : !busy && generated != null
                        ? (savedName == null ? '文件已生成' : '文件已保存')
                        : value?.label ?? '',
                    style: const TextStyle(fontSize: 13, height: 1.6),
                  ),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: value == null || value.total == 0
                        ? 0
                        : value.completed / value.total,
                    minHeight: 3,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: .5),
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: .08),
                  ),
                  if (!busy && generated != null && savedName == null) ...[
                    const SizedBox(height: 12),
                    const AppText(
                      '文件已生成，可重新选择保存位置。',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: AppText(
              error!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 13,
                height: 1.6,
              ),
            ),
          ),
        if (savedName != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: AppText(
              '已保存 · $savedName',
              style: const TextStyle(fontSize: 13, height: 1.6),
            ),
          ),
        const SizedBox(height: 20),
        GlassPillButton(
          key: const ValueKey('book-download-start'),
          icon: CupertinoIcons.arrow_down_to_line,
          label: saving
              ? '正在保存'
              : busy
              ? '正在准备书籍'
              : generated != null
              ? '保存文件'
              : error == null
              ? '下载并保存'
              : '重试下载',
          onPressed: locked ? null : _download,
        ),
        if (busy && !saving)
          GlassTextButton(
            key: const ValueKey('book-download-cancel'),
            onPressed: () => cancellation?.cancel(),
            child: const AppText('取消下载'),
          ),
        const SizedBox(height: 12),
        const AppText(
          '保存前可选择文件夹或云盘位置。已缓存正文会直接复用，取消下载保留已缓存章节。',
          style: TextStyle(fontSize: 12, height: 1.6),
        ),
      ],
    ),
  );
}
