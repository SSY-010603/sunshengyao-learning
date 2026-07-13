# 鸿蒙 Hello World Demo

## 环境要求

- DevEco Studio 5.0+（从华为开发者网站下载）
- HarmonyOS SDK API 12+
- ArkTS / ArkUI

## 运行方式

### 方式一：DevEco Studio 创建项目（推荐）

1. 打开 DevEco Studio → Create Project
2. 选择 **Empty Ability** 模板 → Next
3. Project Name: `HelloWorld`，Language: **ArkTS**，Compatibility: API 12
4. 创建完成后，用本目录下的文件替换对应位置：
   - `entry/src/main/ets/EntryAbility.ets` → 替换项目中的 EntryAbility
   - `entry/src/main/ets/pages/Index.ets` → 替换项目中的 Index 页面
5. 选择模拟器或真机，点 ▶️ Run

### 方式二：直接打开（如项目配置完整）

```bash
# 用 DevEco Studio 直接打开本目录
# 等待 hvigor sync 完成 → Run
```

> 鸿蒙项目依赖 hvigor 构建系统和 oh-package.json5，建议通过 DevEco Studio 模板创建项目后再替换源码。

## Demo 内容

- 页面中央显示 "Hello, 鸿蒙!" 标题
- 点击按钮累计计数，`@State` 变量驱动 UI 自动刷新
- 涵盖：@Entry/@Component 组件声明、@State 响应式状态、Column 布局、Button onClick
