# 知萤 LexiNote · Android

知萤的 Android 手机端工程，使用 Kotlin 和 Jetpack Compose，提供 Markdown 笔记、双向链接、关系图谱、思维导图、白板、版本历史与本地知识库管理。

当前为 `Android` 分支，Android Studio 工程位于仓库根目录。其他平台见 [HarmonyOS](https://github.com/peryixing-lab/LexiNote/tree/HarmonyOS)、[Windows](https://github.com/peryixing-lab/LexiNote/tree/Windows) 和 [macOS](https://github.com/peryixing-lab/LexiNote/tree/macOS)，共享插件与文档见 [main](https://github.com/peryixing-lab/LexiNote/tree/main)。

## 构建与测试

```sh
git clone --branch Android --single-branch https://github.com/peryixing-lab/LexiNote.git
cd LexiNote
./gradlew testDebugUnitTest assembleDebug
```

请在 Android Studio 中安装工程要求的 SDK，并使用本机的 `local.properties` 配置 SDK 路径。工程配置为 compileSdk / targetSdk 37、minSdk 24；Gradle Wrapper 使用 Java 25 工具链。APK 位于 `app/build/outputs/apk/debug/`。

移植说明与原有验证记录见 [Android 移植说明](docs/android-port-notes.md)。

## 贡献与许可

本平台的 PR 请以 `Android` 为目标分支，说明改动、测试环境和验证结果。界面改动请附截图。请勿提交个人笔记、签名密钥、本机 SDK 路径或构建产物。

采用 [GNU GPL v3.0](LICENSE)，第三方声明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
