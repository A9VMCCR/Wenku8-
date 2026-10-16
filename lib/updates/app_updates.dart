import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const updateRepository = String.fromEnvironment(
  'UPDATE_REPOSITORY',
  defaultValue: 'mikufoxxx/Wenku8_Flutter',
);
const currentAppVersion = '0.3.1';
const currentAppBuild = 30;
const currentReleaseNotes = '''
修复检查到新版本却无法获取安装包的问题，兼容旧版客户端升级。
阅读器支持上下滚动、横排翻页与竖排翻页，大屏自动对页阅读。
新增阅读配色、段落排版、分区点按、音量键翻页与自动滚动，字号和行距支持透明预览。
翻页逐段／逐列进入；横排对页先左后右，竖排由右向左。切换排版及折叠／展开保留阅读位置。
隐藏／显示控件时增量调整正文，边缘模糊平滑退场；修复翻页闪字、按钮重叠和状态栏遮挡。
目录按卷展开，支持章节搜索与定位；书签回到段落中部并高亮，系统侧边返回增加退出确认。
新增独立本地书库，支持多选导入 TXT／EPUB、分类和书籍信息编辑；EPUB 支持至 256 MiB。
同系列分卷统一确认合并，可调整卷序、追加新卷或恢复独立，保留插图、进度与书签。
本地原书与合订本只显示在「本地」，不加入书架；旧数据自动整理，原书和阅读记录保留。
新增 OpenList／WebDAV 与实验性夸克网盘导入，通过系统云文档入口手动合并同步书籍和阅读记录。
新增自定义 Microsoft SSML 兼容语音接口；优化听书切段、章级进度、段落高亮与悬浮跟随入口。
新增离线适配与阅读器模式，支持书架「立体书架＋列表／仅列表」切换及标签、分类搜索。
平板采用等宽浏览／详情双栏与多列列表，骨架屏同步适配；优化宽屏详情进退与封面返回落点。
统一液态玻璃开关、滑杆、菜单和阅读配色，修复亮边、Dock 裁切、二级标题及按钮布局。
优化骨架与内容的连续过渡、书评骨架；轻提示自动消失并避开 Dock。
修复玻璃滑块和开关抢占纵向滚动、取消拖动重复提交，以及滚动阅读隐藏控件时的正文重建。
更新奶白剪影图标与中性深灰深色模式，修复分类登录刷新和版本信息缓存，每次打开应用检查更新。
''';

class ReleaseVersion implements Comparable<ReleaseVersion> {
  const ReleaseVersion(this.major, this.minor, this.patch, [this.build = 0]);
  final int major, minor, patch, build;
  static ReleaseVersion? parse(String value) {
    final match = RegExp(
      r'^v?(\d+)\.(\d+)\.(\d+)(?:\+(\d+))?$',
    ).firstMatch(value);
    if (match == null) return null;
    final parts = [for (var i = 1; i <= 4; i++) int.tryParse(match[i] ?? '0')];
    if (parts.any((n) => n == null || n > 2100000000)) return null;
    return ReleaseVersion(parts[0]!, parts[1]!, parts[2]!, parts[3]!);
  }

  String get name => '$major.$minor.$patch';
  @override
  int compareTo(ReleaseVersion other) {
    for (final pair in [
      (major, other.major),
      (minor, other.minor),
      (patch, other.patch),
      (build, other.build),
    ]) {
      final result = pair.$1.compareTo(pair.$2);
      if (result != 0) return result;
    }
    return 0;
  }
}

class InstalledApp {
  const InstalledApp({
    required this.version,
    required this.build,
    required this.abis,
  });
  final String version;
  final int build;
  final List<String> abis;
  ReleaseVersion? get releaseVersion {
    final parsed = ReleaseVersion.parse(version);
    return parsed == null
        ? null
        : ReleaseVersion(parsed.major, parsed.minor, parsed.patch, build);
  }
}

class UpdateAsset {
  const UpdateAsset({
    required this.name,
    required this.url,
    required this.size,
    this.digest,
  });
  final String name;
  final Uri url;
  final int size;
  final String? digest;
}

class AppRelease {
  const AppRelease({
    required this.tag,
    required this.version,
    required this.notes,
    required this.page,
    required this.assets,
  });
  final String tag, notes;
  final ReleaseVersion version;
  final Uri page;
  final List<UpdateAsset> assets;
  static AppRelease? fromGithub(Map<String, dynamic> json, String repository) {
    if (!RegExp(r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$').hasMatch(repository)) {
      throw const FormatException('更新仓库格式错误');
    }
    if (json['draft'] == true || json['prerelease'] == true) return null;
    final tag = json['tag_name'];
    final version = tag is String ? ReleaseVersion.parse(tag) : null;
    if (version == null) return null;
    final assets = <UpdateAsset>[];
    for (final raw in (json['assets'] as List? ?? const [])) {
      if (raw is! Map) continue;
      final name = raw['name'];
      final url = Uri.tryParse(raw['browser_download_url']?.toString() ?? '');
      final size = raw['size'];
      if (name is! String ||
          !name.startsWith('wenku8-') ||
          !name.endsWith('.apk') ||
          url == null ||
          url.scheme != 'https' ||
          url.host != 'github.com' ||
          url.userInfo.isNotEmpty ||
          url.port != 443 ||
          !listEquals(url.pathSegments, [
            ...repository.split('/'),
            'releases',
            'download',
            tag,
            name,
          ]) ||
          size is! int ||
          size <= 0 ||
          size > 300 * 1024 * 1024) {
        continue;
      }
      final digest = raw['digest']?.toString();
      assets.add(
        UpdateAsset(
          name: name,
          url: url,
          size: size,
          digest:
              digest != null &&
                  RegExp(r'^sha256:[a-fA-F0-9]{64}$').hasMatch(digest)
              ? digest.substring(7).toLowerCase()
              : null,
        ),
      );
    }
    return AppRelease(
      tag: tag as String,
      version: version,
      notes: json['body'] is String ? json['body'] as String : '',
      page: Uri.https('github.com', '/$repository/releases/tag/$tag'),
      assets: assets,
    );
  }

  bool isNewerThan(InstalledApp app) {
    final installed = app.releaseVersion;
    if (installed == null) return false;
    final semantic = ReleaseVersion(version.major, version.minor, version.patch)
        .compareTo(
          ReleaseVersion(installed.major, installed.minor, installed.patch),
        );
    return semantic > 0 || (semantic == 0 && version.build > installed.build);
  }

  UpdateAsset? assetFor(List<String> abis) {
    for (final abi in abis) {
      for (final asset in assets) {
        if (asset.name.endsWith('-$abi.apk')) return asset;
      }
    }
    for (final asset in assets) {
      if (asset.name.endsWith('-universal.apk')) return asset;
    }
    return null;
  }
}

abstract interface class UpdatePlatform {
  Future<InstalledApp> installedApp();
  Future<String> install(File apk, String version);
  Future<void> allowInstalls();
  Future<void> openRelease(Uri page);
}

class AndroidUpdatePlatform implements UpdatePlatform {
  static const channel = MethodChannel('org.mewx.wenku8/app_updates');
  @override
  Future<InstalledApp> installedApp() async {
    final info = await channel.invokeMapMethod<String, dynamic>('info');
    if (info == null) throw const FormatException('无法读取当前版本');
    return InstalledApp(
      version: info['version'] as String,
      build: info['build'] as int,
      abis: (info['abis'] as List).cast<String>(),
    );
  }

  @override
  Future<String> install(File apk, String version) async =>
      await channel.invokeMethod<String>('install', {
        'path': apk.path,
        'version': version,
      }) ??
      'opened';
  @override
  Future<void> allowInstalls() => channel.invokeMethod<void>('allowInstalls');
  @override
  Future<void> openRelease(Uri page) =>
      channel.invokeMethod<void>('openRelease', page.toString());
}

class UpdateCancelled implements Exception {}

class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}

class UpdateDownload {
  bool cancelled = false;
  HttpClient? _client;
  void cancel() {
    cancelled = true;
    _client?.close(force: true);
  }

  void check() {
    if (cancelled) throw UpdateCancelled();
  }
}

abstract interface class UpdateSource {
  Future<AppRelease?> latest();
  Future<void> download(
    UpdateAsset asset,
    File file,
    UpdateDownload task,
    void Function(int bytes) progress,
  );
}

class GithubUpdateSource implements UpdateSource {
  GithubUpdateSource({
    this.repository = updateRepository,
    HttpClient Function()? clientFactory,
  }) : _clientFactory = clientFactory ?? HttpClient.new;
  final String repository;
  final HttpClient Function() _clientFactory;
  @override
  Future<AppRelease?> latest() async {
    if (!RegExp(r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$').hasMatch(repository)) {
      throw const FormatException('更新仓库格式错误');
    }
    final client = _clientFactory()
      ..connectionTimeout = const Duration(seconds: 12);
    try {
      final request = await client.getUrl(
        Uri.https('api.github.com', '/repos/$repository/releases/latest'),
      );
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/vnd.github+json',
      );
      request.headers.set(HttpHeaders.userAgentHeader, 'Wenku8-Flutter');
      request.headers.set('X-GitHub-Api-Version', '2022-11-28');
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      if (response.statusCode == 404) return null;
      if (response.statusCode != 200) {
        throw HttpException('GitHub ${response.statusCode}');
      }
      final data = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 20))) {
        data.addAll(chunk);
        if (data.length > 1024 * 1024) throw const FormatException('版本说明过大');
      }
      return AppRelease.fromGithub(
        jsonDecode(utf8.decode(data)) as Map<String, dynamic>,
        repository,
      );
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<void> download(
    UpdateAsset asset,
    File file,
    UpdateDownload task,
    void Function(int bytes) progress,
  ) async {
    final client = _clientFactory()
      ..connectionTimeout = const Duration(seconds: 15);
    task._client = client;
    IOSink? sink;
    try {
      var url = asset.url;
      HttpClientResponse? response;
      for (var hop = 0; hop < 6; hop++) {
        task.check();
        if (url.scheme != 'https' ||
            url.userInfo.isNotEmpty ||
            url.port != 443 ||
            !const {
              'github.com',
              'release-assets.githubusercontent.com',
              'objects.githubusercontent.com',
            }.contains(url.host)) {
          throw const FormatException('安装包下载地址无效');
        }
        final request = await client.getUrl(url);
        request.followRedirects = false;
        final candidate = await request.close().timeout(
          const Duration(seconds: 30),
        );
        if (const [301, 302, 303, 307, 308].contains(candidate.statusCode)) {
          final location = candidate.headers.value(HttpHeaders.locationHeader);
          if (location == null) throw const FormatException('下载重定向无效');
          url = url.resolve(location);
          await candidate.drain<void>();
          continue;
        }
        response = candidate;
        break;
      }
      if (response == null || response.statusCode != 200) {
        throw const HttpException('安装包下载失败');
      }
      sink = file.openWrite();
      var count = 0;
      final digest = _DigestSink();
      final hashing = asset.digest == null
          ? null
          : sha256.startChunkedConversion(digest);
      await for (final chunk in response.timeout(const Duration(seconds: 30))) {
        task.check();
        count += chunk.length;
        if (count > asset.size) throw const FormatException('安装包大小不匹配');
        hashing?.add(chunk);
        sink.add(chunk);
        progress(count);
      }
      hashing?.close();
      await sink.flush();
      task.check();
      if (count != asset.size ||
          (asset.digest != null && digest.value.toString() != asset.digest)) {
        throw const FormatException('安装包校验失败，请重新下载');
      }
    } finally {
      await sink?.close();
      client.close(force: true);
      task._client = null;
    }
  }
}

class AppUpdates extends ChangeNotifier {
  AppUpdates({
    required this.preferences,
    UpdateSource? source,
    UpdatePlatform? platform,
    Future<Directory> Function()? directory,
    DateTime Function()? clock,
  }) : source = source ?? GithubUpdateSource(),
       platform = platform ?? AndroidUpdatePlatform(),
       _directory = directory ?? getTemporaryDirectory,
       _clock = clock ?? DateTime.now;
  final SharedPreferences preferences;
  final UpdateSource source;
  final UpdatePlatform platform;
  final Future<Directory> Function() _directory;
  final DateTime Function() _clock;
  InstalledApp? installed;
  AppRelease? release;
  String? error;
  File? downloaded;
  bool checking = false,
      downloading = false,
      checked = false,
      installing = false,
      needsPermission = false;
  int bytes = 0;
  bool _disposed = false;
  UpdateDownload? _download;
  Future<InstalledApp>? _loadingInfo;
  bool get autoCheck => preferences.getBool('checkAppUpdates') ?? true;
  bool get available =>
      release != null && installed != null && release!.isNewerThan(installed!);
  UpdateAsset? get asset =>
      installed == null ? null : release?.assetFor(installed!.abis);
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> setAutoCheck(bool value) async {
    if (!await preferences.setBool('checkAppUpdates', value)) {
      throw const FileSystemException('设置保存失败');
    }
    _notify();
  }

  Future<void> loadInstalled({bool refresh = false}) async {
    if (_disposed || (!refresh && installed != null)) return;
    try {
      final value = await (_loadingInfo ??= platform.installedApp());
      if (!_disposed) {
        installed = value;
        if (release != null && !available) {
          downloaded = null;
          needsPermission = false;
        }
        _notify();
      }
    } finally {
      _loadingInfo = null;
    }
  }

  Future<void> check({bool automatic = false}) async {
    if (_disposed || checking || downloading) return;
    final now = _clock();
    if (automatic && !autoCheck) return;
    checking = true;
    error = null;
    _notify();
    try {
      await loadInstalled(refresh: true);
      final candidate = await source.latest();
      if (_disposed) return;
      if (candidate?.tag != release?.tag) {
        downloaded = null;
        needsPermission = false;
      }
      release = candidate;
      checked = true;
      await preferences.setInt(
        'lastAppUpdateCheck',
        now.millisecondsSinceEpoch,
      );
    } catch (_) {
      if (!_disposed) error = '无法检查更新，请确认 GitHub 网络连接后重试';
    } finally {
      checking = false;
      _notify();
    }
  }

  Future<void> download() async {
    final selected = asset;
    if (_disposed || downloading || !available || selected == null) return;
    final task = UpdateDownload();
    _download = task;
    downloading = true;
    downloaded = null;
    needsPermission = false;
    error = null;
    bytes = 0;
    _notify();
    File? part;
    try {
      final root = Directory('${(await _directory()).path}/updates');
      await root.create(recursive: true);
      part = File('${root.path}/pending.apk.part');
      final notificationClock = Stopwatch()..start();
      await source.download(selected, part, task, (count) {
        bytes = count;
        if (notificationClock.elapsedMilliseconds >= 100 ||
            count == selected.size) {
          notificationClock.reset();
          _notify();
        }
      });
      task.check();
      final ready = File('${root.path}/update.apk');
      if (await ready.exists()) await ready.delete();
      downloaded = await part.rename(ready.path);
    } catch (failure) {
      if (!task.cancelled && !_disposed) {
        error = failure is FormatException ? failure.message : '下载失败，请检查网络后重试';
      }
    } finally {
      if (part != null && await part.exists()) await part.delete();
      _download = null;
      downloading = false;
      _notify();
    }
  }

  void cancelDownload() => _download?.cancel();
  Future<void> install() async {
    final apk = downloaded;
    if (apk == null || release == null || _disposed || installing) return;
    installing = true;
    _notify();
    try {
      await loadInstalled(refresh: true);
      if (!available) {
        error = '本机已安装 ${installed!.version}（${installed!.build}），无需重复安装';
        return;
      }
      final result = await platform.install(apk, release!.version.name);
      needsPermission = result == 'permission';
      error = null;
    } on PlatformException catch (failure) {
      error = failure.message ?? '无法打开安装程序，请重试';
    } catch (_) {
      error = '无法打开安装程序，请重试';
    } finally {
      installing = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _download?.cancel();
    super.dispose();
  }
}
