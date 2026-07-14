## 用户信息
- 开发方向：客户端
- 已有客户端经验：iOS(A)
- 已有前端经验：无
- 最熟悉的编程语言：C++
- 其他项目经验类型：C++ 开发
- 计算机基础水平：熟悉（操作系统、网络协议、数据结构）

## 公共概念掌握情况

> 两方向互不串通。只会实际初始化学员当前主方向对应的那组；另一组在学员开启二方向后才维护。

### 客户端方向
- UI组件体系：✅(iOS)
- 生命周期：✅(iOS)
- 状态管理与数据绑定：⚪
- 事件处理与用户交互：✅(iOS)
- 导航与路由：✅(iOS)
- 网络通信：⚪
- 数据持久化：⚪
- 多线程与异步编程：⚪
- 权限管理：⚪
- 资源管理与国际化：⚪

### 前端方向
> 学员未开启前端方向，暂不维护。

## 阶段进度

### 客户端 - iOS
- 阶段 1（入门）：✅ 已完成
- 阶段 2（进阶）：⚪ 未开始
- 阶段 3（完备）：⚪ 未开始

## 学习进度

### 客户端 - iOS 基础
最近学习时间：2026-07-14
已掌握知识点：
- UIView 是 iOS UI 的基类，视图层级是树状结构（basics/01.md）
- UIKit 常用控件：UILabel、UIButton、UIImageView 等（basics/01.md）
- Auto Layout 约束布局与 UIStackView 自动排列（basics/01.md）
- 命令式（UIKit）vs 声明式（SwiftUI）两种 UI 范式（basics/01.md）
- UIViewController 生命周期：viewDidLoad(一次性) / viewWillAppear(每次可见) / deinit(释放)（basics/02.md）
- App 级生命周期：前后台切换，后台约 5 秒保存时间（basics/02.md）
- 生命周期回调中常见陷阱：忘了清理监听器/定时器导致内存泄漏（basics/02.md）
- 触摸事件三阶段：began/moved/ended，hitTest 命中测试找被点视图，响应链向上冒泡找处理者（basics/03.md）
- UIControl + Target-Action 封装触摸为语义化事件，UIGestureRecognizer 处理复杂手势（basics/03.md）
- UIImageView 默认不响应事件，需设置 isUserInteractionEnabled（basics/03.md）
- 导航栈：Push 入栈/Pop 出栈，UINavigationController 管理导航栏和栈操作（basics/04.md）
- Push（层级导航）vs Present（模态弹出），TabBar 管理同级切换（basics/04.md）
- 页面传值：直接赋值（正向）、闭包回调（简单反向）、Delegate 代理（复杂反向）（basics/04.md）
- 典型架构：UITabBarController + UINavigationController（basics/04.md）

### 客户端 - iOS Crash 排障
最近学习时间：2026-07-14
已掌握知识点：
- Zombie Object = 访问已释放的对象（use-after-free），典型场景：Timer没清理/闭包强引用/delegate非weak/KVO没移除（crash/01-zombie.md）
- 排障工具：NSZombieEnabled快速定位类名、Instruments看完整生命周期、ASan给释放/访问双调用栈（crash/01-zombie.md）
- 生产监控思路：hook dealloc + 延迟释放 + 采样上报，或基于crash报告调用栈归因（crash/01-zombie.md）
