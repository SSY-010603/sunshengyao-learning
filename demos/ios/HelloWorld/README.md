# iOS Hello World Demo

## 环境要求

- macOS 14.0+
- Xcode 15.0+（从 App Store 安装）
- iOS Simulator（Xcode 内置）

## 运行方式

### 方式一：Xcode 创建项目（推荐）

1. 打开 Xcode → Create a new Xcode project
2. 选择 **App** → Next
3. Product Name: `HelloWorld`，Interface: **UIKit App Delegate**，Language: **Swift**
4. 创建完成后，用本目录下的 `AppDelegate.swift` 和 `ViewController.swift` 替换项目中对应文件
5. 选择 iPhone 模拟器，点 ▶️ Run

### 方式二：Swift Package（命令行快速验证）

```bash
# 初始化一个最小组件包
mkdir -p HelloWorldApp && cd HelloWorldApp
swift package init --type executable
# 然后将 Package.swift 的 target 指向本目录源码
```

> 实际开发中推荐方式一，Xcode 项目模板会自动处理 Info.plist、Assets 等配置。

## Demo 内容

- 页面中央显示 "Hello, iOS!" 标题
- 点击按钮累计计数并更新标题文字
- 涵盖：UIView 层级、Auto Layout、Target-Action 事件绑定、UIViewController
