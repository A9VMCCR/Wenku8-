import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_ui.dart';
import 'cover_arrival.dart';
import 'legacy_transport.dart';
import 'local_book_media.dart';

typedef IllustrationRequest = Future<Uint8List> Function(String url);

/// Decoded images are bounded by Flutter's image cache; encoded images by bytes,
/// not by chapter count. Completed futures are not retained after eviction.
class ReaderIllustrationCache {
  ReaderIllustrationCache({
    IllustrationRequest? request,
    this.maxBytes = 16 * 1024 * 1024,
  }) : _request = request ?? LegacyTransport.illustration;
  static final shared = ReaderIllustrationCache();
  final IllustrationRequest _request;
  final int maxBytes;
  final _pending = <String, Future<Uint8List>>{};
  final _cache = <String, Uint8List>{};
  // Header inspection is shared by the inline view and gallery. Weak byte keys
  // follow the encoded cache, without retaining another copy of an illustration.
  static final _sizes = Expando<Size>('illustration-size');
  static final _sizeRequests = Expando<Future<Size>>('illustration-size-read');
  int _bytes = 0;
  int _epoch = 0;
  int get encodedBytes => _bytes;
  Uint8List? peek(String url) => _cache[url];
  Size? sizeOf(String url) {
    final bytes = peek(url);
    return bytes == null ? null : _sizes[bytes];
  }

  Future<Size> _size(Uint8List bytes) => _sizeRequests[bytes] ??= () async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    try {
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      try {
        final size = Size(
          descriptor.width.toDouble(),
          descriptor.height.toDouble(),
        );
        if (size.isEmpty) throw const FormatException('插图尺寸无效');
        _sizes[bytes] = size;
        return size;
      } finally {
        descriptor.dispose();
      }
    } finally {
      buffer.dispose();
    }
  }();

  void evict(String url) {
    final bytes = _cache.remove(url);
    if (bytes != null) _bytes -= bytes.length;
  }

  Future<Uint8List> load(String url) {
    final cached = _cache.remove(url);
    if (cached != null) {
      _cache[url] = cached;
      return Future.value(cached);
    }
    return _pending.putIfAbsent(url, () async {
      final epoch = _epoch;
      try {
        final bytes = url.startsWith('wenku-local:')
            ? await LocalBookMedia.load(url)
            : await _request(url);
        if (bytes.isEmpty || bytes.length > 8 * 1024 * 1024) {
          throw const FormatException('插图大小无效');
        }
        if (epoch == _epoch && bytes.length <= maxBytes) {
          while (_bytes + bytes.length > maxBytes && _cache.isNotEmpty) {
            _bytes -= _cache.remove(_cache.keys.first)!.length;
          }
          _cache[url] = bytes;
          _bytes += bytes.length;
        }
        return bytes;
      } finally {
        if (epoch == _epoch) _pending.remove(url);
      }
    });
  }

  void clearMemory() {
    _epoch++;
    _cache.clear();
    _pending.clear();
    _bytes = 0;
  }
}

/// Scrolling illustrations use their own aspect ratio and the actual text
/// column width. Page illustrations instead use the whole leaf without cropping.
class ReaderIllustrationFrame extends StatelessWidget {
  const ReaderIllustrationFrame({
    super.key,
    required this.child,
    this.imageSize,
    this.fitPage = false,
  });

  final Widget child;
  final Size? imageSize;
  final bool fitPage;

  @override
  Widget build(BuildContext context) {
    if (fitPage) return SizedBox.expand(child: child);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        return AnimatedSize(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: width,
            height: width / (imageSize?.aspectRatio ?? .75),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(ArchiveDesign.panelRadius),
              child: child,
            ),
          ),
        );
      },
    );
  }
}

class ReaderIllustration extends StatefulWidget {
  const ReaderIllustration({
    super.key,
    required this.url,
    this.onOpen,
    this.cache,
    this.fullScreen = false,
    this.fitPage = false,
  });
  final String url;
  final VoidCallback? onOpen;
  final ReaderIllustrationCache? cache;
  final bool fullScreen;
  final bool fitPage;
  @override
  State<ReaderIllustration> createState() => _ReaderIllustrationState();
}

class _ReaderIllustrationState extends State<ReaderIllustration> {
  ReaderIllustrationCache get _cache =>
      widget.cache ?? ReaderIllustrationCache.shared;
  late Future<({Uint8List? bytes, Size? size, Object? error})> _future =
      _load();
  Future<({Uint8List? bytes, Size? size, Object? error})> _load() async {
    try {
      final cache = _cache, url = widget.url;
      final bytes = await cache.load(url);
      final size = await cache._size(bytes);
      return (bytes: bytes, size: size, error: null);
    } catch (error) {
      return (bytes: null, size: null, error: error);
    }
  }

  @override
  void didUpdateWidget(ReaderIllustration old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url || old.cache != widget.cache) _future = _load();
  }

  @override
  Widget build(BuildContext context) {
    final cached = _cache.peek(widget.url), size = _cache.sizeOf(widget.url);
    return RepaintBoundary(
      child: FutureBuilder<({Uint8List? bytes, Size? size, Object? error})>(
        key: ObjectKey(_future),
        future: _future,
        initialData: cached != null && size != null
            ? (bytes: cached, size: size, error: null)
            : null,
        builder: (context, snapshot) {
          final bytes = snapshot.data?.bytes;
          Widget frame(Widget child) => ReaderIllustrationFrame(
            imageSize: snapshot.data?.size,
            fitPage: widget.fullScreen || widget.fitPage,
            child: child,
          );
          if (snapshot.data?.error != null) {
            return frame(
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(CupertinoIcons.photo, size: 28),
                    const SizedBox(height: 12),
                    const Text('插图加载失败'),
                    GlassTextButton(
                      onPressed: () {
                        _cache.evict(widget.url);
                        setState(() {
                          _future = _load();
                        });
                      },
                      child: const Text('重试插图'),
                    ),
                  ],
                ),
              ),
            );
          }
          if (bytes == null) {
            return frame(
              const LoadingSkeleton(
                layout: SkeletonLayout.cover,
                label: '正在载入插图',
              ),
            );
          }
          return frame(
            LayoutBuilder(
              builder: (context, constraints) => GestureDetector(
                onTap: widget.onOpen,
                child: Semantics(
                  label: '章节插图，点击查看大图',
                  image: true,
                  child: Image.memory(
                    bytes,
                    width: constraints.maxWidth,
                    height: constraints.maxHeight,
                    fit: BoxFit.contain,
                    cacheWidth: widget.fullScreen
                        ? 2400
                        : (constraints.maxWidth *
                                  MediaQuery.devicePixelRatioOf(context))
                              .round()
                              .clamp(1, 1600),
                    frameBuilder: (context, child, frame, sync) => CoverArrival(
                      bytes: bytes,
                      ready: frame != null,
                      placeholder: const LoadingSkeleton(
                        layout: SkeletonLayout.cover,
                        label: '正在解码插图',
                      ),
                      child: child,
                    ),
                    errorBuilder: (context, error, stack) => Center(
                      child: GlassTextButton(
                        onPressed: () {
                          _cache.evict(widget.url);
                          setState(() {
                            _future = _load();
                          });
                        },
                        child: const Text('重新读取插图'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class ReaderIllustrationGallery extends StatefulWidget {
  const ReaderIllustrationGallery({
    super.key,
    required this.urls,
    required this.initialUrl,
    this.cache,
  }) : assert(urls.length > 0);
  final List<String> urls;
  final String initialUrl;
  final ReaderIllustrationCache? cache;
  @override
  State<ReaderIllustrationGallery> createState() =>
      _ReaderIllustrationGalleryState();
}

class _ReaderIllustrationGalleryState extends State<ReaderIllustrationGallery> {
  late int _page = widget.urls
      .indexOf(widget.initialUrl)
      .clamp(0, widget.urls.length - 1);
  late final _pages = PageController(initialPage: _page);
  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Atmosphere(
      child: GlassHeaderLayout(
        header: ArchiveHeaderBar(
          leading: GlassIconButton(
            icon: CupertinoIcons.back,
            label: '返回阅读',
            onPressed: () => Navigator.pop(context),
          ),
          title: ArchiveRouteTitle(
            title: '章节插图',
            code: 'IMAGE / ${_page + 1} OF ${widget.urls.length}',
          ),
        ),
        body: Padding(
          padding: EdgeInsets.only(
            top:
                MediaQuery.paddingOf(context).top + FrostedHeader.toolbarHeight,
            bottom: MediaQuery.paddingOf(context).bottom,
          ),
          child: PageView.builder(
            controller: _pages,
            itemCount: widget.urls.length,
            onPageChanged: (page) => setState(() => _page = page),
            itemBuilder: (context, index) => InteractiveViewer(
              key: ValueKey(widget.urls[index]),
              minScale: 1,
              maxScale: 5,
              child: SizedBox.expand(
                child: ReaderIllustration(
                  url: widget.urls[index],
                  cache: widget.cache,
                  fullScreen: true,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
