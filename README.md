<p align="center">
  <img src="assets/branding/app-icon.png" width="96" alt="Wenku8 Flutter" />
</p>

<h1 align="center">Wenku8 Flutter</h1>

<p align="center">基于 Flutter 的 Android 轻小说阅读客户端</p>

<p align="center">
  <a href="https://github.com/mikufoxxx/Wenku8_Flutter/releases"><img src="https://img.shields.io/github/v/release/mikufoxxx/Wenku8_Flutter?style=flat-square&color=555555" alt="Release" /></a>
  <a href="https://github.com/mikufoxxx/Wenku8_Flutter/actions/workflows/flutter-ci.yml"><img src="https://github.com/mikufoxxx/Wenku8_Flutter/actions/workflows/flutter-ci.yml/badge.svg?branch=master" alt="Build" /></a>
  <img src="https://img.shields.io/badge/Platform-Android-555555?style=flat-square" alt="Android" />
  <a href="assets/licenses/GPL-3.0.txt"><img src="https://img.shields.io/badge/License-GPL--3.0-555555?style=flat-square" alt="GPL 3.0" /></a>
</p>

<p align="center">
  <a href="https://github.com/mikufoxxx/Wenku8_Flutter/releases">下载</a> ·
  <a href="CHANGELOG.md">更新日志</a> ·
  <a href="https://github.com/mikufoxxx/Wenku8_Flutter/issues">问题反馈</a> ·
  <a href="docs/RELEASING.md">构建指南</a>
</p>

## 简介

Wenku8 Flutter 是轻小说文库客户端的 Flutter 重构版本，面向 Android，集成书籍发现、书架管理、阅读、离线缓存与在线听书。界面采用半透明材质与档案式排版，提供立体书架、连贯的页面过渡和可自定义的阅读体验。

## 界面预览

<p align="center">
  <img src="docs/images/discovery.png" width="30%" alt="发现" />
  &nbsp;
  <img src="docs/images/reader.png" width="30%" alt="阅读器" />
  &nbsp;
  <img src="docs/images/settings.png" width="30%" alt="设置" />
</p>

## 功能特性

- **书籍发现**：分类、排行、书名与作者搜索、出版文库。
- **立体书架**：循环轮播、惯性滚动、吸附定位与触觉反馈。
- **阅读排版**：上下滚动、横排翻页与竖排翻页，大屏对页；阅读配色、字号、行距、页边距、段落间距、缩进与对齐，系统字体与内置思源宋体，支持实时预览。
- **阅读工具**：可展开的分卷目录、书签定位与高亮、章内查找、插图查看、分区点按与音量键翻页、自动滚动。
- **离线阅读**：章节缓存、缓存管理、阅读历史、进度续读与本地备份。
- **本地书库**：多选导入 TXT、EPUB，同系列分卷合并，保留目录、插图与阅读记录；支持分类整理、OpenList／WebDAV 与夸克网盘导入，以及系统云文档同步。
- **在线听书**：中文音色、自定义 Microsoft SSML 接口、语速调节、段落跟随、睡眠定时、后台与锁屏控制。
- **账号与社区**：文库账号、云书架、书评与回复。
- **性能设置**：低性能设备模式，可独立调整玻璃折射、模糊、动效与立体书架。
- **使用方式**：离线时隐藏发现、书架只显示已缓存收藏；阅读器模式只保留本地与设置。

## 下载

从 [GitHub Releases](https://github.com/mikufoxxx/Wenku8_Flutter/releases) 下载 APK。提供 `arm64-v8a`、`armeabi-v7a` 与 `x86_64` 三种架构，常见 Android 手机请选择 **arm64-v8a**。

安装后，可在 **设置 → 关于轻小说文库** 查看版本信息、更新说明并检查更新。

阅读与自定义语音见 [阅读器与本地书库](docs/READER.md)，网盘连接见 [网盘导入指南](docs/CLOUD_IMPORT.md)，标签与关键词用法见 [搜索指南](docs/SEARCH.md)。

## 构建

开发环境：**Flutter 3.41.5 / Dart 3.11.3、JDK 17、Android SDK**。

```sh
git clone https://github.com/mikufoxxx/Wenku8_Flutter.git
cd Wenku8_Flutter
flutter pub get
flutter build apk --release --target-platform android-arm64
```

### GitHub Actions

- [Flutter Android](https://github.com/mikufoxxx/Wenku8_Flutter/actions/workflows/flutter-ci.yml)：代码检查、自动测试与 ARM64 APK 构建。
- [Build Android APKs](https://github.com/mikufoxxx/Wenku8_Flutter/actions/workflows/android-release.yml)：三架构签名 APK、源码归档与版本发布候选，支持版本标签触发和手动运行。

签名配置与发布流程见 [构建发布指南](docs/RELEASING.md)。

## 贡献

欢迎通过 [Issues](https://github.com/mikufoxxx/Wenku8_Flutter/issues) 反馈问题或提出建议，通过 Pull Request 参与开发。提交问题时请提供应用版本、Android 版本和复现步骤。

## 致谢与许可

本项目基于 [MewX/light-novel-library_Wenku8_Android](https://github.com/MewX/light-novel-library_Wenku8_Android) 重构。感谢 MewX、Baby Pepper（SeraphRoy）、Jack Liu（aaassseee）及原项目贡献者。

- 应用源码：保留原项目 [GPL v2 或后续版本声明](LICENSE)，本 Flutter 组合版本按 [GPL v3](assets/licenses/GPL-3.0.txt) 分发。
- 内置字体：[Adobe Source Han Serif CN](https://github.com/adobe-fonts/source-han-serif)，[SIL OFL 1.1](assets/fonts/OFL-SourceHanSerif.txt)。
- 在线语音协议适配：[rany2/edge-tts](https://github.com/rany2/edge-tts)，[LGPL v3](assets/licenses/edge-tts.txt)。

完整版权声明与接口运行库分发条件见 [NOTICE](NOTICE) 和 [第三方组件许可](docs/THIRD_PARTY.md)。
