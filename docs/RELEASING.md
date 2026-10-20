# 构建公开源码预览

公开工程用于阅读器、界面和本地书库开发，在线组件未包含。构建后的应用名为「轻小说文库 · 源码预览」，使用独立包名 `org.mewx.wenku8_flutter.source_preview`，不会覆盖正式版或访问其应用数据。

## 本地构建

环境：Flutter 3.41.5、Dart 3.11.3、JDK 17、Android SDK。

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --release --target-platform android-arm64
cd android
./gradlew :app:testReleaseUnitTest
```

预览支持本地导入、阅读、书架、缓存记录和界面开发。文库联网入口会提示在线组件未包含；不会发起文库请求或把失败伪装成成功。源码预览不是正式升级包，不应上传到稳定更新渠道。

未配置签名时使用本机调试证书。自己的签名可配置在 `android/key.properties`，字段为 `storeFile`、`storePassword`、`keyAlias`、`keyPassword`；密钥、文件和本机路径不要提交到 Git。

## 导出源码

在项目根目录执行：

```sh
python3 tools/export_public_source.py ../Wenku8_Flutter-public-source
python3 tools/check_public_source.py ../Wenku8_Flutter-public-source
```

输出目录必须为空。脚本保留公开源文件、测试、资源、平台工程和许可，排除本机配置、密钥、日志、截图、构建产物和开发记录；导出前检查受限组件与已识别凭据，失败时不写出目录。`--source-only` 为兼容旧调用保留，不能放宽边界。

检查覆盖已知路径和特征，提交前仍需审阅实际差异；仅从新源码包排除文件，不会清除 Git 历史中的旧内容。

## GitHub Actions

[Flutter source checks](../.github/workflows/flutter-ci.yml) 在主分支、Pull Request 或手动运行时执行源码检查、Flutter 与原生测试、独立预览构建。它不读取正式签名，不上传 APK，也不创建或更新 Release。公开工程不提供在线组件注入或正式发布流程。

## 许可与分发

保留原项目的 `LICENSE`、`NOTICE`、`assets/licenses/` 和各第三方组件源码与声明。本 Flutter 组合版本使用 GPL version 3；在线听书适配与文档导入库等仍适用各自许可，见 [第三方组件与分发条件](THIRD_PARTY.md)。

公开源码预览不是历史正式 APK 的完整对应源码。分发任何组合产物前，应按实际组件核对对应源码、署名与分发授权，不能仅凭排除某个文件推定满足许可义务。
