# Android Hello World Demo

## 环境要求

- Android Studio Hedgehog (2023.1.1)+
- Android SDK 34
- Kotlin 1.9+

## 运行方式

### 方式一：Android Studio 直接打开（推荐）

1. 打开 Android Studio → Open an Existing Project
2. 选择本目录 `demos/android/HelloWorld`
3. 等待 Gradle Sync 完成
4. 选择模拟器或真机，点 ▶️ Run

### 方式二：命令行构建

```bash
cd demos/android/HelloWorld
./gradlew assembleDebug
# APK 产出在 app/build/outputs/apk/debug/
```

> 首次运行需要 Gradle 同步和网络下载依赖，可能需要几分钟。

## Demo 内容

- 页面中央显示 "Hello, Android!" 标题
- 点击按钮累计计数并更新标题文字
- 涵盖：Activity、XML 布局（ConstraintLayout）、findViewById、setOnClickListener
