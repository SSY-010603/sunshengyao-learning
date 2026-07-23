## 我的信息
- 开发方向：客户端
- 已有客户端经验：iOS(A)
- 已有前端经验：无
- 最熟悉的编程语言：C++
- 日常开发语言：Objective-C 为主，C/C++ 辅助；Swift 优先级低，有需求时 AI 编码即可
- 其他项目经验类型：C++ 开发
- 计算机基础水平：熟悉（操作系统、网络协议、数据结构）

## 公共概念掌握情况

> 两方向互不串通。只会实际初始化当前主方向对应的那组；另一组在开启二方向后才维护。

### 客户端方向
- UI组件体系：✅(iOS)
- 生命周期：✅(iOS)
- 状态管理与数据绑定：✅(iOS)
- 事件处理与用户交互：✅(iOS)
- 导航与路由：✅(iOS)
- 网络通信：✅(iOS)
- 数据持久化：✅(iOS)
- 多线程与异步编程：✅(iOS)
- 权限管理：✅(iOS)
- 资源管理与国际化：✅(iOS)

### 前端方向
> 未开启前端方向，暂不维护。

## 阶段进度

### 客户端 - iOS
- 阶段 1（入门）：✅ 已完成
- 阶段 2（进阶）：✅ 已完成
- 阶段 3（完备）：✅ 已完成

## 学习进度

### 客户端 - iOS 基础
最近学习时间：2026-07-17
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
- KVO 属性级观察：运行时动态子类 hook setter，必须 removeObserver，直接改 ivar 不触发（basics/05.md）
- NSNotification 全局广播：完全解耦，系统通知（前后台切换等）是常见用例（basics/05.md）
- Delegate + 手动刷新：最朴素最常用的状态管理方式（basics/05.md）
- ObjC MVVM：手动 MVVM，VC 不碰 Model、VM 不引用 UIKit（basics/05.md）
- 列表刷新：先改 Model 再通知 View，增量刷新数据源不同步会 crash（basics/05.md）
- URLSession 三件套：Configuration + Session + DataTask，回调在子线程（basics/06.md）
- NSJSONSerialization：JSON 映射 Foundation 对象，null 是 NSNull、类型可能混淆（basics/06.md）
- YYModel：一行字典转模型，自动处理类型转换和 null 过滤（basics/06.md）
- 三层错误处理：网络层 → HTTP 层 → 业务层（basics/06.md）
- SDWebImage：一行加载+内存缓存+磁盘缓存（basics/06.md）
- NetworkManager 封装：公共 header、token、统一错误码（basics/06.md）
- ATS：要求 HTTPS，Info.plist 临时豁免，上线前必须去掉（basics/06.md）
- UserDefaults：少量键值，非立即写盘，类型要匹配，不能存大数据（basics/07.md）
- 沙盒目录：Documents(持久+备份) / Caches(缓存+可清理) / tmp(临时)（basics/07.md）
- NSCache：内存 LRU 缓存，系统内存不足自动淘汰（basics/07.md）
- FMDB：SQLite 封装，占位符防注入，FMDatabaseQueue 保线程安全，事务保原子性（basics/07.md）
- 数据库迁移：PRAGMA user_version + ALTER TABLE（basics/07.md）
- Core Data：了解即可，新项目不建议用（basics/07.md）
- 主线程铁律：所有 UI 操作必须在主线程（basics/08.md）
- GCD：串行/并发队列，sync 死锁，五种模式（后台+回主线程/group/after/once/barrier）（basics/08.md）
- OperationQueue：支持取消、依赖、并发数控制（basics/08.md）
- 线程陷阱：竞态条件、Block 捕获变量时机、异步回调 self 生命周期（basics/08.md）

### 客户端 - iOS Crash 排障
最近学习时间：2026-07-20
已掌握知识点：
- Zombie Object = 访问已释放的对象（use-after-free），典型场景：Timer没清理/闭包强引用/delegate非weak/KVO没移除（crash/01-zombie.md）
- 排障工具：NSZombieEnabled快速定位类名、Instruments看完整生命周期、ASan给释放/访问双调用栈（crash/01-zombie.md）
- 生产监控思路：hook dealloc + 延迟释放 + 采样上报，或基于crash报告调用栈归因（crash/01-zombie.md）
- SIGABRT = 进程主动 abort，绝大多数来自 NSException 未捕获；NSException vs NSError：前者不可恢复（throw），后者可恢复（返回值）（crash/02-sigabrt.md）
- 四类常见 NSException：NSRangeException（越界）、NSInvalidArgumentException（插nil/unrecognized selector）、NSInternalInconsistencyException（断言）、KVO 重复移除（crash/02-sigabrt.md）
- NSAssert 在 Release 下是 no-op，生产兜底要手动 if + raise（crash/02-sigabrt.md）
- ObjC 异常和 C++ 异常是两套机制，跨语言不互通，混编时 C++ 侧自己 try-catch 翻译成 NSException（crash/02-sigabrt.md）
- Watchdog 机制：主线程卡 8 秒会被杀进程（信号 0x8badf00d），典型场景是 dispatch_sync 死锁（crash/02-sigabrt.md）
- try-catch 谨慎用：解析不可信数据兜底、KVO 移除兜底是合理场景，不能当控制流（crash/02-sigabrt.md）
- 排障三板斧：Exception Breakpoint（开发）、symbolicatecrash/atos（线上符号化）、hook objc_exception_throw（监控）（crash/02-sigabrt.md）

### 客户端 - iOS 阶段 3
最近学习时间：2026-07-23
已掌握知识点：
- 权限四步流程：Info.plist 声明 → 检查状态 → 请求授权 → 处理结果（basics/09.md）
- Info.plist 权限键和用途描述审核要求，文案必须写清具体用途（basics/09.md）
- 四态状态机：NotDetermined / Authorized / Denied / Restricted（basics/09.md）
- 相机权限：AVCaptureDevice API，回调在任意线程需回主线程（basics/09.md）
- 相册权限：iOS 14+ Limited 模式，读写权限分离（basics/09.md）
- 定位权限：WhenInUse / Always 两级授权，后台定位审核严（basics/09.md）
- ATT 跟踪权限：iOS 14.5+，IDFA 获取前提（basics/09.md）
- 权限撤销处理：进入前台时重新检查，提供降级方案（basics/09.md）
- 授权时机：用户主动触发 + 预解释模式，授权率最高（basics/09.md）
- Asset Catalog 管理图片：自动切片、自动适配深色模式、App Thinning 按需加载（basics/10.md）
- imageNamed 缓存机制 + 大图用 imageWithContentsOfFile（basics/10.md）
- NSLocalizedString + .strings 实现多语言（basics/10.md）
- 复数处理用 .stringsdict 配合 NSStringPluralRuleType（basics/10.md）
- 字符串拼接陷阱：不同语言语序不同，必须用完整带占位符的翻译（basics/10.md）
- 日期/数字格式化用 NSDateFormatter / NSNumberFormatter（basics/10.md）
- 深色模式：dynamicColorNamed + Asset Catalog 颜色 + traitCollectionDidChange（basics/10.md）
- Dynamic Type：preferredFontForTextStyle + adjustsFontForContentSizeCategory（basics/10.md）
- 实战模式：封装 R 类统一管理资源（basics/10.md）
