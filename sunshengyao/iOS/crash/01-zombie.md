# iOS Crash 疑难排障 #1：Zombie Object（僵尸对象）

> **专题**：Crash 疑难排障 · 第 1 篇
> **我的背景锚点**：C++ use-after-free 经验、日常 ObjC + C/C++ 开发、iOS 基础语法水平
> **代码风格**：本文所有示例以 **Objective-C 为主**（你日常写的语言），Swift 仅在对比差异时提及

---

## 一句话定义

**Zombie = 访问已释放的对象。**

C++ 里叫 use-after-free，iOS 里叫 zombie——对象内存已经被回收了，但某个指针还指向那块旧地址，再通过这个指针发消息，就炸了。

---

## 从 C++ 直觉出发

```cpp
// C++ — use-after-free，你应该很熟悉
class Dog {
public:
    void bark() { std::cout << "woof" << std::endl; }
    int age = 3;
};

Dog* d = new Dog();
delete d;       // 内存已释放，归还给系统
d->bark();      // 💥 未定义行为：可能崩、可能不崩、可能输出乱码
d->age;         // 💥 同上——那块内存已经不是你的了
```

关键特征：**不稳定复现**。有时候恰好那块内存没被覆盖，`d->bark()` 还能"正常"执行；下次内存被别的东西占用了，就崩了。这是 use-after-free 最恶心的地方——你测的时候不崩，上线后用户崩。

iOS 的 zombie 完全一样，只是触发方式是给已释放对象发 ObjC 消息：

```objc
// Objective-C（MRC 手动引用计数下）
// ⚠️ ARC 下不允许手动调 release，这里用 MRC 语法仅为演示 zombie 原理
NSObject* obj = [[NSObject alloc] init];  // 引用计数 = 1
[obj release];                           // 引用计数 = 0，对象被 dealloc
[obj description];                       // 💥 EXC_BAD_ACCESS — 给已释放对象发消息
```

**C++ 和 ObjC 的关键差异**：

| | C++ | ObjC |
|---|---|---|
| 访问方式 | `d->bark()` 直接调用成员函数 | `[obj description]` 通过 `objc_msgSend` 发消息 |
| 崩溃机制 | 虚表/成员地址可能无效 → 未定义行为 | isa 指针指向无效内存 → `objc_msgSend` 崩溃 |
| 典型信号 | 段错误 / 随机崩溃 | `EXC_BAD_ACCESS` 在 `objc_msgSend` |
| 不稳定复现 | ✅ 同一个 | ✅ 同一个 |

---

## ARC 下的对象生死

理解 zombie 前必须搞清楚 iOS 对象是怎么"死"的。ARC（Automatic Reference Counting）自动管理引用计数——编译器在编译时自动插入 `retain`/`release`/`autorelease` 调用，你不需要手动写。

```
创建对象     → 引用计数 = 1
强引用它     → 引用计数 +1（strong，默认行为）
强引用释放   → 引用计数 -1（离开作用域 / 置 nil）
引用计数 = 0 → 系统调用 dealloc，对象被释放
```

### ObjC 三种引用类型

| 类型 | 关键字 | 对引用计数的影响 | 对象释放后的行为 |
|------|--------|-----------------|-----------------|
| **强引用** | `strong`（默认） | +1 | 不影响——强引用存在期间对象不会被释放 |
| **弱引用** | `weak` | 0 | 对象释放后**自动置 nil** → 安全，不会 zombie |
| **不安全引用** | `unsafe_unretained` | 0 | 对象释放后**不置 nil** → 访问时崩溃（类似 C++ 裸指针） |

> **C++ 类比**：`strong` ≈ `std::shared_ptr`（共享所有权，引用计数归零才释放），`weak` ≈ `std::weak_ptr`（对象销毁后自动过期），`unsafe_unretained` ≈ 裸指针 `T*`（对象销毁后指针不置空，访问即崩）。

### ⚠️ ObjC 里还有一个大坑：`assign` vs `weak`

在 ObjC 的 `@property` 声明里，对象类型有两种"不持有"的修饰：

```objc
// ARC 时代的正确写法
@property (nonatomic, weak) id<SomeDelegate> delegate;        // ✅ 释放后自动置 nil

// MRC 时代的遗留写法——ARC 下编译通过但不安全
@property (nonatomic, assign) id<SomeDelegate> delegate;      // ❌ 释放后不置 nil → zombie
```

| | `weak` | `assign` |
|---|---|---|
| 引用计数 | 0（不持有） | 0（不持有） |
| 对象释放后 | **自动置 nil** | **不置 nil，还是旧地址** |
| 之后访问 | 安全（nil 不崩） | 💥 zombie |
| ARC 支持 | ✅ 完全支持 | ⚠️ 编译通过但不安全 |

**`assign` 对对象类型永远是安全隐患**。`assign` 本来是给非对象类型用的（`NSInteger`、`CGFloat`、`C 结构体`等），在 MRC 时代被广泛用于 delegate，ARC 引入后应该全部改为 `weak`，但老代码里大量遗留。

> 在 ARC 引入前（2011 年前），`assign` 是 ObjC delegate 的标准写法。如果你的项目有历史代码，混编头文件巡检是必须做的——后文"场景 4"详述。

### Zombie 的根本原因

**持有对象的强引用被清零（对象被 dealloc），但某个裸引用（unsafe_unretained / assign / 裸指针）还指向那块旧内存。**

```
A 持有 B（strong）        → B 的引用计数 = 1
A 释放对 B 的强引用        → B 的引用计数 = 0 → B 被 dealloc
C 通过 weak 持有 B        → B 释放后 weak 自动变 nil → C 访问 nil → 安全 ✅
C 通过 unsafe_unretained   → B 释放后还是旧地址 → C 访问 → 崩溃 💥
C 通过 assign 持有 B       → 同上 → 崩溃 💥
C 通过 __unsafe_unretained → 同上 → 崩溃 💥
```

---

## 典型 Zombie 场景（5 类）

### 场景 1：Timer / NSTimer 没清理

最常见的 zombie 陷阱：

```objc
// ❌ 危险写法：NSTimer target-action 方式
@interface MyViewController : UIViewController
@property (nonatomic, strong) NSTimer *timer;
@end

@implementation MyViewController

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    // NSTimer 强引用 target(self)
    self.timer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                  target:self
                                                selector:@selector(updateUI)
                                                userInfo:nil
                                                 repeats:YES];
    // self(强引用) → timer，timer(强引用) → self → 循环引用
    // 结果：两者都泄漏，dealloc 永远不被调用
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    // 如果忘了在这里 invalidate，VC 被 pop 后 timer 还在跑
    // 如果用了 target-action，timer 还强引用 self，不会 dealloc → 泄漏
    self.timer = nil;  // ❌ nil 了属性但没 invalidate，timer 还在 RunLoop 里
}

@end
```

**正确的清理方式**：

```objc
- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [self.timer invalidate];  // ✅ 先 invalidate（从 RunLoop 移除 + 打破对 target 的强引用）
    self.timer = nil;         // ✅ 再置 nil
}
```

**翻车链路**：

```
1. target-action → self 和 timer 循环引用 → 泄漏（不是 zombie）
2. 某个时机手动 invalidate → 打破循环 → self 被 dealloc
3. 但 RunLoop 中可能还持有对 timer 的调度安排（invalidate 和 RunLoop 移除不是原子操作）
4. timer 下次 fire 时给已释放的 self 发消息 → zombie
```

> **iOS 10+ 的闭包 API**：`[NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^{ ... }]`，闭包不强引用 target，配合 `__weak typeof(self) weakSelf = self;` 使用更安全。但很多老代码库还在用 target-action。

### 场景 2：Block 闭包强引用 self

```objc
// ❌ 危险写法：block 直接捕获 self
- (void)loadImage {
    [ImageLoader shared].loadCompletion = ^(UIImage *image) {
        self.avatarView.image = image;  // block 强引用 self
    };
    // self(强引用) → ImageLoader(强引用) → block(强引用) → self → 循环引用
    // self 无法释放 → 泄漏
}

// ✅ 正确写法：weak-strong dance
- (void)loadImage {
    __weak typeof(self) weakSelf = self;
    [ImageLoader shared].loadCompletion = ^(UIImage *image) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;  // self 已释放，安全退出
        strongSelf.avatarView.image = image;
    };
}
```

> **为什么要 weak-strong dance 而不是只写 weak？** `weakSelf` 保证 block 不强引用 self（打破循环引用）。`strongSelf` 保证在 block 执行期间 self 不会被释放（防止执行到一半 self 被 dealloc 变 zombie）。只用 weak 不用 strong，block 执行期间 self 可能被其他线程释放。

### 场景 3：Delegate 没用 weak

```objc
// ❌ 错误：delegate 用了 strong（默认）或 assign
@interface MyManager : NSObject
@property (nonatomic, strong) id<MyDelegate> delegate;    // ❌ strong delegate
@end

// ✅ 正确：delegate 必须 weak
@interface MyManager : NSObject
@property (nonatomic, weak) id<MyDelegate> delegate;      // ✅ weak delegate
@end
```

经典循环引用模式：VC.delegate = manager，manager.delegate = VC。如果 delegate 是 strong，VC 和 manager 互相持有 → 泄漏。一旦外部打破循环（比如手动 delegate = nil），其中一方被释放后另一方还持有旧指针 → zombie。

如果用的是 `assign`：不构成循环引用（assign 不增加引用计数），但 delegate 指向的对象被释放后 assign 不置 nil → 直接 zombie。

### 场景 4：`assign` property（ObjC 混编重灾区）

这是 ObjC 项目里最隐蔽的 zombie 来源：

```objc
// ObjC 头文件 — 10 年前的标准写法
@interface SomeOldClass : NSObject
@property (nonatomic, assign) id<SomeDelegate> delegate;  // ❌ 2011 年前的遗留
@end

// 当 delegate 指向的 VC 被释放后：
// - weak property：自动 delegate = nil ✅
// - assign property：delegate 还是旧地址 → 给已释放对象发消息 → zombie 💥
```

**为什么 assign 在 ARC 下编译通过？** ARC 只管理 `strong`/`weak` 的引用计数自动加减。`assign` 对对象类型在 ARC 下的语义是"不持有，不管生死"——编译器不报错，但 runtime 不保护。Apple 没有把它标记为 deprecated（为了兼容 MRC 代码），但它对对象类型**永远是安全隐患**。

> **实操建议**：用脚本扫描所有 `.h` 文件中 `@property (nonatomic, assign) id` 模式的声明，逐个改为 `weak`。非对象类型（NSInteger、CGFloat、struct）保留 assign 不受影响。

### 场景 5：KVO 未正确移除

```objc
// 添加观察
[someObj addObserver:self forKeyPath:@"value" options:NSKeyValueObservingOptionNew context:NULL];

// ❌ 如果忘了在 dealloc 前移除
// self 被 dealloc 后，someObj 发 KVO 通知还会尝试调用 self 的 observeValueForKeyPath: → zombie

// ✅ 正确做法
- (void)dealloc {
    [someObj removeObserver:self forKeyPath:@"value"];
}
```

> **⚠️ 注意**：如果存在循环引用导致 `dealloc` 不被调用，那 KVO 也不会移除——泄漏，不是 zombie。但循环引用被打破后，KVO 移除和 dealloc 的顺序可能出问题，导致 zombie。

---

## Zombie Crash 的症状

| 症状 | 说明 |
|------|------|
| **EXC_BAD_ACCESS (code=1)** | 读取了已释放的内存 |
| **EXC_BAD_ACCESS (code=2)** | 写入了已释放的内存 |
| **崩溃在 `objc_msgSend`** | 调用栈里看到 `objc_msgSend` — 在给已释放对象发消息 |
| **不稳定复现** | 同一个操作有时崩有时不崩 — 典型的 zombie 特征 |
| **崩溃地址看起来像有效对象** | 地址曾是合法的对象地址，只是内存已被回收 |

### 典型崩溃堆栈

```
Thread 0 Crashed:
0  libobjc.A.dylib     objc_msgSend + 16
1  MyApp               -[SomeManager notifyDelegate] + 48
2  MyApp               -[SomeManager onDataLoaded] + 120
```

**关键信号**：崩溃在 `objc_msgSend` — 意味着"给一个对象发消息，但那个对象的 isa 指针指向了无效内存"。

---

## 排障工具箱

### 工具 1：NSZombieEnabled（首选，最快定位）

**原理**：开启后，runtime 在对象 dealloc 时**不真正回收内存**，而是把对象的 isa 指针替换为一个特殊的 zombie class（如 `_NSZombie_MyViewController`）。当你再给这个 zombie 对象发消息时，zombie class 的 `forwardInvocation:` 会打印明确日志。

**Xcode 中开启**：

1. Product → Scheme → Edit Scheme → Run → Diagnostics
2. 勾选 **Zombie Objects** ✅
3. 运行 App，复现崩溃

**控制台输出**：

```
*** -[MyViewController respondsToSelector:]: message sent to deallocated instance 0x7fe8a3c0
```

直接告诉你：`MyViewController` 已被释放，但你还在给它发 `respondsToSelector:` 消息。

**在代码中开启**（适合 CI 或无法用 Xcode Scheme 的场景）：

```objc
// AppDelegate.m — 仅 Debug 模式
- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
#ifdef DEBUG
    setenv("NSZombieEnabled", "YES", 1);
    setenv("NSDeallocateZombies", "YES", 1);
#endif
    return YES;
}
```

> `NSDeallocateZombies` = YES 表示 zombie 对象最终也会被释放（防止内存无限增长），但会在释放前留足够时间让你捕获日志。

**⚠️ 绝对不能用于生产环境**：Zombie 模式会阻止内存及时回收，导致内存持续增长，最终 OOM。

### 工具 2：Instruments — Zombies 模板

比 Xcode 的 Zombie 开关更强大，能看到完整的对象生命周期：

1. Xcode → Open Developer Tool → Instruments
2. 选择 **Zombies** 模板
3. 选择你的 App，点 Record
4. 复现崩溃

Instruments 会显示：
- 哪个类被 zombie 访问了
- 什么时候 `alloc` 的
- 什么时候 `dealloc` 的
- **谁在 dealloc 之后还给它发了消息**（点击 zombie 事件可看调用栈）

**优势**：不只告诉你"对象已释放"，还能告诉你**对象是怎么死的**以及**谁在它死后还访问了它**。

### 工具 3：Address Sanitizer（ASan）

Xcode 7+ 引入，能检测多种内存错误（不只是 zombie）：

1. Product → Scheme → Edit Scheme → Run → Diagnostics
2. 勾选 **Address Sanitizer**
3. 运行后，ASan 会在访问已释放内存时**立即中断**，并显示双调用栈

```
=================================================================
==12345==ERROR: AddressSanitizer: heap-use-after-free on 0x603000012345
READ of size 8 at 0x603000012345
    #0 0x10a2b3c in objc_msgSend
    #1 0x10a1f4d in -[MyVC viewDidAppear:]
previously freed by thread T0 here:
    #0 0x10b2a3c in free
    #1 0x10a1f00 in -[MyVC dealloc]
```

**ASan 的优势**：同时给出"释放调用栈"和"非法访问调用栈"，直接看到是哪里释放的、哪里又访问了。

> **⚠️ 注意**：ASan 和 Zombie Objects **不能同时开启**，二选一。ASan 性能开销更大（约 2x 慢），但信息更全。Zombie 模式更轻量，适合快速确认。

### 工具 4：Malloc Scribble（辅助确认）

Malloc Scribble 会在对象释放后把那块内存填充为特定模式（`0xAA`），这样如果你访问了已释放内存，读到的不是随机数据而是 `0xAA`，更容易确认是 use-after-free：

1. Product → Scheme → Edit Scheme → Diagnostics
2. 勾选 **Malloc Scribble**
3. 崩溃时检查内存内容是否为 `0xAA` 模式

这个工具**不主动中断**，只改内存内容，适合辅助判断，不适合独立排障。

### 工具选择策略

| 场景 | 推荐工具 | 理由 |
|------|---------|------|
| 只想快速确认"是不是 zombie" | NSZombieEnabled | 一行日志直接出类名 |
| 需要看对象完整生命周期 | Instruments Zombies | 能追踪 alloc → dealloc 全链路 |
| 需要精确的释放/访问调用栈 | Address Sanitizer | 双调用栈，最精确 |
| 已确认是 zombie 但想辅助定位 | Malloc Scribble | 辅助确认，不独立使用 |

---

## 排障五步法

### 第一步：确认是 Zombie

1. 开启 NSZombieEnabled
2. 复现崩溃
3. 控制台输出 `message sent to deallocated instance` → ✅ **确认是 zombie**
4. 没有这条日志 → 不是 zombie，去查其他方向（野指针 / 栈溢出 / 系统内部错误）

### 第二步：定位"谁被释放了"

从 zombie 日志中直接读取类名和地址：

```
*** -[MyViewController respondsToSelector:]: message sent to deallocated instance 0x7fe8a3c0
         ↑ 这个类就是被释放的对象                          ↑ 这是它的旧地址
```

### 第三步：找出"谁在释放后还访问"

看崩溃时的调用栈：

```
0  objc_msgSend
1  -[SomeManager notifyDelegate]     ← 这里在给已释放的 VC 发消息
2  -[SomeManager onDataLoaded]
```

### 第四步：找出"对象为什么被释放"

这是最关键的步骤。常见原因排查清单：

| 检查项 | 怎么查 |
|--------|--------|
| delegate 是 strong 还是 weak？ | 搜索 `@property *delegate` 看修饰词 |
| block 是否用了 `__weak self`？ | 搜索 block 内的 `self->` 或 `self.` 调用 |
| NSTimer 是否在 `viewDidDisappear` 中 invalidate？ | 检查 timer 的生命周期管理 |
| KVO 是否在 dealloc 前 remove？ | 搜索 `addObserver` 确认有对应 `removeObserver` |
| NSNotificationCenter 是否在 dealloc 前 remove？ | 同上 |
| ObjC 的 `@property` 是否用了 assign 而非 weak？ | 搜索 `@property (nonatomic, assign) id` |
| `__unsafe_unretained` 是否用在了可能先释放的场景？ | 搜索 `__unsafe_unretained` 使用位置 |

### 第五步：修复

| 原因 | 修复 |
|------|------|
| delegate 是 strong | 改为 `@property (nonatomic, weak)` |
| block 强引用 self | 用 `__weak typeof(self) weakSelf = self;` + weak-strong dance |
| Timer 没清理 | `viewDidDisappear` 中 `[timer invalidate]` + `self.timer = nil` |
| KVO 没移除 | dealloc 前 `removeObserver` |
| ObjC assign property | 改为 `weak` |
| `__unsafe_unretained` 误用 | 改为 `__weak` 或确保生命周期对齐 |

---

## 生产环境的 Zombie 监控

调试工具只能用在开发阶段。但 zombie crash 恰恰最需要线上数据来定位——因为你本地可能复现不了。以下是三类生产环境方案：

### 方案 1：Hook dealloc（自建基建）

**核心思路**：swizzle `dealloc`，在对象释放后不立即回收内存，而是把 isa 替换为 zombie class，短暂保留（3-10 秒），期间如果有人给这个 zombie 对象发消息，就在 zombie class 的 `forwardInvocation:` 中记录类名和调用栈上报。

```objc
// 伪代码示意 — 生产环境 Zombie 检测的核心思路
// 1. swizzle dealloc：释放后将对象 isa 指向一个特殊的 zombie class
// 2. 当消息发给 zombie class 时，在 forwardInvocation: 中记录类名和调用栈上报
// 3. 延迟一段时间后真正释放内存

static void swizzled_dealloc(id self, SEL _cmd) {
    const char *className = class_getName(object_getClass(self));
    // 将 isa 替换为 _NSZombie_OriginalClass，对象"变成"zombie
    NSString *zombieClassName = [NSString stringWithFormat:@"_NSZombie_%s", className];
    Class zombieClass = NSClassFromString(zombieClassName);
    if (zombieClass) {
        object_setClass(self, zombieClass);
    }
    // 将对象地址 + 类名记入一个纯 C 结构体的延迟释放队列
    // （绝不能在 block 里捕获 self，block 会强引用 zombie 对象导致永远不释放）
    // 延迟队列会在 N 秒后批量调用原始 dealloc 真正释放
}
```

**关键设计考量**：

- **不能永不释放**（会 OOM），只能短暂保留 3-10 秒后真正 dealloc
- **必须采样**：不是所有类都 hook，只 hook 可疑的类（如自定义 VC / View），否则内存压力太大
- **性能策略**：直接 hook `objc_msgSend` 开销极大（它是全 App 调用频率最高的函数）；更实际的做法是 hook `dealloc` + 在 zombie class 的 `forwardInvocation:` 中上报
- **配合 crash 上报**：zombie 检测结果需要随 crash 报告一起上报（如 PLCrashReporter、KSCrash）
- **延迟队列实现**：用纯 C 数组 / 结构体记录地址+类名+入队时间，**不能 block 捕获 self**

### 方案 2：基于 Crash 报告的归因

不主动检测 zombie，而是在收到 EXC_BAD_ACCESS crash 报告后，通过调用栈特征归因判断：

```
1. 崩溃在 objc_msgSend              → 很可能 zombie
2. 调用栈中出现 -[XXXX dealloc]      → XXXX 类是嫌疑对象
3. 结合模块/页面信息                  → 猜测是哪个 VC/View 被提前释放
4. 结合崩溃前的用户操作路径           → 猜测触发时机（如"pop VC 后立即收到回调"）
```

这种方式零性能开销，但只能事后猜测，不能确认。

### 方案 3：FBRetainCycleDetector（Facebook 开源）

不直接检测 zombie，而是检测**循环引用**——zombie 的前因之一：

```objc
// 用法示意（简化）
FBRetainCycleDetector *detector = [[FBRetainCycleDetector alloc] initWithObject:viewController];
NSSet *retainCycles = [detector findRetainCycles];
// retainCycles 会返回发现的循环引用路径，如：
// VC → block → VC  或  VC → timer → VC
```

这个工具解决的是"泄漏"问题，间接防止"泄漏打破后变 zombie"。但它不能检测 `unsafe_unretained` / `assign` 导致的 zombie。

---

## 防范 Zombie 的编码规范

| 规范 | 说明 | ObjC 正确示例 |
|------|------|---------------|
| **delegate 一律 weak** | 无例外 | `@property (nonatomic, weak) id<SomeDelegate> delegate;` |
| **block 默认 weak self** | 除非能 100% 确认 block 生命周期 ≤ self | `__weak typeof(self) weakSelf = self;` + weak-strong dance |
| **NSTimer 用 block API** | iOS 10+ 用 block-based API，避免 target-action | `[NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^{ ... }]` |
| **viewDidDisappear 清理** | timer、通知监听、KVO 都在这里 invalidate/remove | 不要指望 dealloc 会调（循环引用会阻止） |
| **`__unsafe_unretained` 慎用** | 只在两个对象生命周期严格一致时用，否则用 weak | 不确定就用 weak，多一次 nil 判断比崩好 |
| **混编头文件巡检** | 扫描 `.h` 里 `@property (nonatomic, assign) id` 模式，逐个改 weak | assign 对对象类型永远是安全隐患 |
| **dealloc 日志** | Debug 下每个关键类的 dealloc 都打日志 | 确认对象是否被按时释放，泄漏早发现 |

---

## 关键要点总结

1. **Zombie = use-after-free**，C++ 里叫 `delete` 后访问，ObjC 里叫给已释放对象发消息，本质一样
2. **ARC 不是万能的**：ARC 只管引用计数的自动加减，不管 weak/unsafe_unretained/block/Timer 的误用
3. **泄漏和 zombie 是因果关系**：循环引用导致泄漏，泄漏被打破后裸引用变 zombie
4. **5 类典型场景**：Timer 没清理、block 强引用 self、delegate 非 weak、ObjC assign property、KVO 未移除
5. **排障首选 NSZombieEnabled**，一行日志直接定位类名；需要调用栈用 ASan；需要生命周期全貌用 Instruments
6. **生产监控靠基建**：hook dealloc + 延迟释放 + 采样上报，或基于 crash 报告的调用栈归因
7. **防范重于排障**：delegate 一律 weak、block 默认 weak self、Timer 用 block API、混编头文件巡检

---

## 📊 学习进度

- **当前端**：iOS
- **当前专题**：Crash 疑难排障
- **本文覆盖**：Zombie Object 的原理、典型场景、排障工具、生产监控方案、防范规范
- **整体进度**：阶段 1 ✅ 已完成 | 阶段 2 ⚪ 未开始 | 阶段 3 ⚪ 未开始
- **当前能力等级**：已掌握 iOS 基础 UI 开发；正在建立 crash 疑难排障能力
- **下一里程碑**：掌握更多 crash 类型（如 EXC_BAD_ACCESS 非 zombie 场景、SIGABRT、卡死等）

---

## 我的反馈

> **【我理解到的核心】为必填项**，其他可选。

### 我理解到的核心 ✅必填
（用自己的话复述本文最核心的 2-3 个要点；空着的话 Agent 会拒绝生成下一篇）

### 还有疑问的地方
（卡点写这里，Agent 会重点处理）
