# iOS Crash 疑难排障：Zombie Object（僵尸对象）

> **专题**：Crash 疑难排障 · 第 1 篇
> **前置知识**：ARC 内存管理基础、Instruments 工具使用

---

## 什么是 Zombie Object

先用 C++ 直觉理解：

```cpp
// C++ 的同类问题 —— use-after-free
class Dog {
public:
    void bark() { printf("woof\n"); }
};

Dog* d = new Dog();
delete d;       // 内存已释放
d->bark();      // 💥 未定义行为：可能崩、可能不崩、可能输出乱码
```

iOS 里的 Zombie 就是一回事——对象被释放了，你还在发消息给它：

```objc
// Objective-C 版本
NSObject* obj = [[NSObject alloc] init];
[obj release];      // ARC 下自动发生，对象被释放
[obj description];  // 💥 EXC_BAD_ACCESS
```

```swift
// Swift 里更隐蔽——通常发生在 Swift 和 ObjC 互调的边界
let vc = SomeObjCViewController()
// VC 被 pop 后被释放，但某个闭包/定时器还持有旧引用
vc.title  // 💥 可能触发 zombie
```

**关键区别**：C++ 里 `delete` 后访问是"未定义行为"，可能崩也可能不崩。ObjC 里给已释放对象发消息，同样是未定义行为——有时候恰好那块内存没被覆盖，消息还能"成功"执行，你以为没问题；下次那块内存被别的东西占用了，就崩了。这就是 zombie crash 难排查的原因——**不稳定性，难以稳定复现**。

---

## ARC 下的内存管理速览

理解 zombie 前要搞清楚 iOS 对象是怎么"死"的。ARC（Automatic Reference Counting）自动管理引用计数：

```
创建对象     → 引用计数 = 1
强引用它     → 引用计数 +1
强引用释放   → 引用计数 -1
引用计数 = 0 → 对象被释放（dealloc）
```

### 引用类型

| 类型 | 关键字 | 行为 | 对引用计数的影响 |
|------|--------|------|-----------------|
| **强引用** | `strong`（默认） | 持有对象，不让它释放 | +1 |
| **弱引用** | `weak` | 不持有，对象释放后自动置 nil | 0（自动置 nil 安全） |
| **无主引用** | `unowned` | 不持有，对象释放后不置 nil | 0（访问时崩溃） |

### Zombie 产生的根本原因

**强引用被意外清零，但弱引用或裸指针仍然指向那块内存。**

```
A 持有 B（strong）    → B 的引用计数 = 1
A 释放对 B 的强引用     → B 的引用计数 = 0 → B 被 dealloc
C 持有对 B 的弱引用     → B 已释放，weak 自动置 nil ✅ 安全
C 持有对 B 的 unowned   → B 已释放，unowned 不置 nil → 访问 💥 崩溃
C 通过 unsafe 指针持有 B → B 已释放，指针还是旧地址 → 访问 💥 崩溃
```

---

## Zombie Crash 的典型场景

### 场景 1：Timer / Notification 没清理

最常见，和 02.md 里讲的陷阱一脉相承：

```swift
class MyViewController: UIViewController {
    var timer: Timer?
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // timer 的 target 是 self（强引用）
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateUI()  // ✅ 用了 weak self，安全
        }
        // ❌ 但如果用 target-action 方式：
        // timer = Timer.scheduledTimer(timeInterval: 1.0, target: self, 
        //                              selector: #selector(updateUI), userInfo: nil, repeats: true)
        // timer 强引用 self，self 强引用 timer → 循环引用 → 看似不会释放
        // 但如果在外部强制断开（比如 assign nil 给 timer），self 被 dealloc 后
        // timer 的下一次 fire 还会尝试调用 self.updateUI → zombie
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        timer?.invalidate()
        timer = nil
    }
}
```

**常见翻车方式**：
- `viewDidDisappear` 里忘了 invalidate → VC 被 pop 后 timer 还在跑 → zombie
- `deinit` 里才 invalidate → 但强引用循环导致 deinit 根本不会被调用 → 泄漏 + 潜在 zombie

### 场景 2：闭包捕获了已释放的对象

```swift
class ProfileViewController: UIViewController {
    let avatarView = UIImageView()
    
    func loadImage() {
        ImageLoader.shared.load(url: avatarURL) { [weak self] image in
            // ✅ weak self 防止循环引用
            // 但如果 self 已释放，self?.avatarView 不会执行
            self?.avatarView.image = image  // ✅ 安全
        }
        
        // ❌ 危险写法：
        ImageLoader.shared.load(url: avatarURL) { image in
            self.avatarView.image = image  // 强引用 self
            // 如果 VC 在回调前就被释放了，这里就是 zombie
        }
    }
}
```

### 场景 3：Delegate 没用 weak

```swift
// ❌ 错误：delegate 用了 strong（默认）
class TableViewController: UIViewController {
    var delegate: SomeDelegate?  // 默认 strong！
}

// ✅ 正确：delegate 必须 weak
class TableViewController: UIViewController {
    weak var delegate: SomeDelegate?
}
```

这是 iOS 开发里最经典的循环引用模式：A.delegate = B，B.owningView = A。如果 delegate 是 strong，A 和 B 互相持有，谁都不会释放。一旦外部强制打破循环，其中一方被释放后另一方还持有旧指针 → zombie。

### 场景 4：ObjC 和 Swift 混编边界

```swift
// ObjC 代码
@property (nonatomic, weak) id<SomeDelegate> delegate;

// Swift 调用方
objCInstance.delegate = self  // self 被 weak 引用
// ObjC 对象释放后，delegate 自动置 nil ✅

// 但如果 ObjC 端用的是 assign（而非 weak）：
@property (nonatomic, assign) id<SomeDelegate> delegate;  // ❌ 危险！
// ObjC 对象释放后，delegate 不会置 nil → zombie
```

**重点**：老 ObjC 代码里大量使用 `assign` 而非 `weak`。在 ARC 引入前，`assign` 是 delegate 的常见写法。混编时这是重灾区。

### 场景 5：KVO 未正确移除

```swift
// 添加观察
someObj.addObserver(self, forKeyPath: "value", options: .new, context: nil)

// ❌ 如果忘了在 deinit 里移除
// someObj 被 dealloc 后，KVO 通知机制还会尝试调用 self.observeValue → zombie

// ✅ 正确做法
deinit {
    someObj.removeObserver(self, forKeyPath: "value")
}
```

---

## Zombie Crash 的症状

| 症状 | 说明 |
|------|------|
| **EXC_BAD_ACCESS (code=1)** | 访问了已释放的内存。最典型的 zombie 信号 |
| **EXC_BAD_ACCESS (code=2)** | 写入已释放的内存 |
| **崩溃在 objc_msgSend** | 调栈里看到 `objc_msgSend` — 在给已释放对象发消息 |
| **崩溃在 autorelease 之后** | 对象被 drain 掉后，还通过指针访问 |
| **不稳定复现** | 同一个操作有时崩有时不崩 — 典型的 zombie 特征 |
| **崩溃地址在 obj-c 对象区域** | 崩溃地址看起来像是一个曾经有效的对象地址 |

### 典型崩溃堆栈

```
Thread 0 Crashed:
0  libobjc.A.dylib     objc_msgSend + 16
1  MyApp               -[SomeViewController viewDidAppear:] + 48
2  UIKit               -[UIViewController _viewDidAppear:] + 120
```

关键信号：**崩溃在 `objc_msgSend`** — 意思是"给一个对象发消息，但那个对象已经不是有效的对象了"。

---

## 排障工具箱

### 工具 1：NSZombieEnabled（首选）

这是排查 zombie 最直接的工具。原理：当对象被释放时，runtime 不真正回收内存，而是把它标记为 "zombie"，保留类名信息。当你再给这个对象发消息时，runtime 会打印明确的日志告诉你"你给一个已释放的 XXX 类对象发了消息"，而不是默默崩溃。

**Xcode 中开启方式**：

1. Edit Scheme → Run → Diagnostics
2. 勾选 **Zombie Objects**
3. 运行 App，复现崩溃

**控制台输出示例**：

```
*** -[MyViewController respondsToSelector:]: message sent to deallocated instance 0x7fe8a3c0
```

这就直接告诉你：MyViewController 已被释放，但你还在给它发消息。

**在代码中开启**（适合无法用 Xcode 的场景）：

```swift
// 在 AppDelegate 的 didFinishLaunching 中
func application(_ application: UIApplication, 
                 didFinishLaunchingWithOptions launchOptions: ...) -> Bool {
    // 仅在 Debug 模式下开启
    #if DEBUG
    setenv("NSZombieEnabled", "YES", 1)
    setenv("NSDeallocateZombies", "YES", 1)
    #endif
    return true
}
```

**⚠️ 注意**：Zombie 模式会阻止内存回收，导致内存持续增长。**只用于调试，绝不能带入生产环境**。

### 工具 2：Instruments - Zombies 模板

比 Xcode 的 Zombie 开关更强大，能看到完整的对象生命周期：

1. Xcode → Open Developer Tool → Instruments
2. 选择 **Zombies** 模板
3. 选择你的 App，点 Record
4. 复现崩溃
5. Instruments 会显示：哪个类、什么时候 alloc、什么时候 dealloc、谁在 dealloc 后还发消息

**Instruments 的优势**：
- 能看到"谁释放了对象"和"谁在释放后还访问了对象"
- 可以看到对象的完整历史（alloc → retain → release → dealloc → zombie 访问）
- 不只是告诉你"对象已释放"，还能告诉你"对象是怎么死的"

### 工具 3：Malloc Scribble（辅助定位）

Malloc Scribble 会在对象释放后把那块内存填充为特定模式（0xAA），这样如果你访问了已释放的内存，读到的不是随机数据而是 0xAA，更容易判断这是 zombie：

1. Edit Scheme → Run → Diagnostics
2. 勾选 **Malloc Scribble**
3. 运行后崩溃时，检查内存内容是否为 0xAA 模式

### 工具 4：Address Sanitizer (ASan)

Apple 在 Xcode 7+ 引入的工具，能检测多种内存问题：

1. Edit Scheme → Run → Diagnostics
2. 勾选 **Address Sanitizer**
3. 运行后，ASan 会在访问已释放内存时立即中断，并显示详细的分配/释放调用栈

```
// ASan 输出示例：
=================================================================
==12345==ERROR: AddressSanitizer: heap-use-after-free on 0x603000012345
READ of size 8 at 0x603000012345
#0 0x10a2b3c in objc_msgSend 
#1 0x10a1f4d in -[MyVC viewDidAppear:]
previously freed by thread T0 here:
#0 0x10b2a3c in free
#1 0x10a1f00 in -[MyVC dealloc]
```

**ASan 比 Zombie 的优势**：能同时给出"释放调用栈"和"非法访问调用栈"，直接看到是哪里释放的、哪里又访问了。

### 工具选择总结

| 工具 | 适用场景 | 优点 | 缺点 |
|------|---------|------|------|
| **NSZombieEnabled** | 快速确认是否是 zombie | 一行日志直接定位类名 | 不给调用栈，不知道谁释放的 |
| **Instruments Zombies** | 需要完整对象历史 | 能看 alloc→dealloc 全链路 | 操作复杂，对性能影响大 |
| **Address Sanitizer** | 需要精确的释放/访问调用栈 | 同时给两边调用栈 | 性能开销大，部分场景有误报 |
| **Malloc Scribble** | 辅助判断是否访问已释放内存 | 简单 | 只改内存内容，不主动中断 |

---

## 排障实战流程

### 第一步：确认是 Zombie

1. 开启 NSZombieEnabled，复现崩溃
2. 如果控制台输出 `message sent to deallocated instance` → **确认是 zombie**
3. 如果没输出 → 不是 zombie，去查其他方向（如栈溢出、系统 bug）

### 第二步：定位"谁被释放了"

从 zombie 日志中读取类名：

```
*** -[MyViewController respondsToSelector:]: message sent to deallocated instance 0x7fe8a3c0
                                    ↑
                              这个类就是被释放的对象
```

### 第三步：找出"谁在释放后还访问"

看崩溃时的调用栈：

```
0  objc_msgSend
1  -[SomeManager notifyDelegate]     ← 这里在给已释放的 VC 发消息
```

### 第四步：找出"对象为什么被释放"

这是最关键的步骤。常见原因排查清单：

| 检查项 | 怎么查 |
|--------|--------|
| delegate 是 strong 还是 weak？ | 搜索 `var delegate` 看有没有 `weak` |
| 闭包是否用了 weak self？ | 搜索闭包内的 `self.` 调用 |
| Timer 是否在 viewDidDisappear 中 invalidate？ | 检查 timer 的生命周期管理 |
| KVO 是否在 deinit 中 removeObserver？ | 搜索 `addObserver` 确认有对应 remove |
| NotificationCenter 是否在 deinit 中 removeObserver？ | 同上 |
| ObjC 的 property 是否用了 assign 而非 weak？ | 检查混编头文件 |
| unowned 是否用在了可能先释放的场景？ | 检查 `unowned` 使用位置 |

### 第五步：修复

根据原因选择对应修复：

| 原因 | 修复 |
|------|------|
| delegate 是 strong | 改为 `weak var delegate` |
| 闭包强引用 self | 改为 `[weak self] in` |
| Timer 没清理 | `viewDidDisappear` 中 invalidate + nil |
| KVO 没移除 | `deinit` 中 removeObserver |
| ObjC assign property | 改为 `weak` |
| unowned 误用 | 改为 `weak` 或确保生命周期对齐 |

---

## 生产环境的 Zombie 监控

调试工具不能用在生产环境。但 zombie crash 又是最需要线上数据来排查的。以下是常见方案：

### 方案 1：Hook objc_msgSend（自建基建）

在 runtime 层面拦截 `objc_msgSend`，检测目标对象是否是已释放的 zombie：

```objc
// 伪代码示意
// swizzle dealloc，释放后将对象 isa 指向一个特殊的 zombie class
// 当消息发给 zombie class 时，记录类名和调用栈
static void swizzled_dealloc(id self, SEL _cmd) {
    // 不真正释放，而是把 isa 替换为 _NSZombie_OriginalClass
    object_setClass(self, NSClassFromString([NSString stringWithFormat:@"_NSZombie_%s", 
                                              class_getName(object_getClass(self))]));
    // 延迟真正释放（比如 5 秒后）
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
        // 真正释放
        orig_dealloc(self, _cmd);
    });
}
```

**关键设计考量**：
- 不能像调试 Zombie 那样永不释放（会 OOM），只能短暂保留
- 需要采样：不是所有对象都 hook，只 hook 可疑的类
- 性能开销要控制：objc_msgSend 是全 App 调用频率最高的函数，hook 它对性能影响大
- 需要配合 crash 上报系统（如 PLCrashReporter、KSCrash）把 zombie 检测结果随 crash 报告一起上报

### 方案 2：基于 Crash 报告的归因

不主动检测 zombie，而是在收到 EXC_BAD_ACCESS crash 报告后，通过调用栈归因判断：

```
1. 崩溃在 objc_msgSend → 很可能 zombie
2. 调用栈中出现 -[XXXX dealloc] → XXXX 类是嫌疑对象
3. 结合模块/页面信息 → 猜测是哪个 VC/View 被提前释放
```

### 方案 3：FBRetainCycleDetector（Facebook 开源）

检测循环引用，间接防止 zombie：

```swift
// 用法
let detector = FBRetainCycleDetector(object: viewController)
let retainCycles = detector.findRetainCycles()
// retainCycles 会返回发现的循环引用路径
```

这个不直接检测 zombie，但循环引用是 zombie 的前因之一——要么循环引用导致泄漏，要么打破循环引用后一方变 zombie。

---

## 防范 Zombie 的编码规范

| 规范 | 说明 |
|------|------|
| **delegate 一律 weak** | 无例外 |
| **闭包默认 [weak self]** | 除非你能 100% 确认闭包生命周期短于 self |
| **Timer 用闭包 API** | `Timer.scheduledTimer(withTimeInterval:repeats:block:)` 比 target-action 安全 |
| **viewDidDisappear 清理** | timer、通知监听、KVO 都在这里 invalidate/remove |
| **unowned 慎用** | 只在两个对象生命周期严格一致时用（如 VC 和它的 view），否则用 weak |
| **混编头文件巡检** | 扫描 ObjC `.h` 里的 `assign` property，逐个改为 `weak` |
| **dealloc 日志** | Debug 下每个关键类的 dealloc 都打日志，确认对象是否被按时释放 |

---

## 关键要点总结

1. **Zombie = 访问已释放的对象**，C++ 叫 use-after-free，iOS 叫 zombie，本质一样
2. **ARC 不是万能的**，ARC 只管引用计数自动加减，不管 weak/unowned/闭包/Timer 的误用
3. **典型场景**：Timer 没清理、闭包强引用 self、delegate 非 weak、KVO 没移除、ObjC assign property
4. **排障首选 NSZombieEnabled**，一行日志直接定位类名；需要调用栈用 Instruments 或 ASan
5. **生产监控靠基建**：hook dealloc + 延迟释放 + 采样上报，或者基于 crash 报告的调用栈归因
6. **防范重于排障**：delegate 一律 weak、闭包默认 [weak self]、Timer 用闭包 API、混编头文件巡检

---

## 我的反馈

> 在每个小节下写几句即可。**【我理解到的核心】为必填项**，其他可选。

### 我理解到的核心 ✅必填
（用自己的话复述本文最核心的 2-3 个要点；空着的话 Agent 会拒绝生成下一篇）

### 还有疑问的地方
（卡点写这里，Agent 会重点处理）

### 想深入的方向
（可选）

### 联想到的（其他技术/经验）
（可选，帮 Agent 找类比锚点）
