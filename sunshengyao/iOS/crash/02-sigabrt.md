# 02 — SIGABRT：ObjC 异常导致的崩溃

> 本文是 Crash 疑难排障系列第 2 篇。上一篇 `01-zombie.md` 讲了 EXC_BAD_ACCESS 信号下的 zombie 场景，本篇讲另一大类高频 crash——SIGABRT 信号，也就是 ObjC 异常（NSException）和 C++ 异常导致的崩溃。

---

## 一句话定义

**SIGABRT** = 进程主动调用 `abort()` 结束自己，通常是因为触发了**未被捕获的异常**或**断言失败**。在 iOS ObjC 开发中，绝大多数 SIGABRT 来自 NSException 未被 try-catch 兜住。

---

## C++ 直觉

```
C++ 里：
- std::runtime_error 抛出 → 没 try-catch → std::terminate → abort() → SIGABRT
- assert(false) → abort() → SIGABRT
- std::terminate 被触发（如 noexcept 函数抛异常）→ abort() → SIGABRT

iOS ObjC 里：
- @throw [NSException exceptionWithName:...] → 没 @catch → uncaught handler → abort()
- NSAssert(false, ...) → 抛 NSException → 同上
- NSArray objectAtIndex: 越界 → 抛 NSRangeException → 同上
- 主线程同步 dispatch（你在 08.md 学过）→ 死锁 → watchdog 杀进程 → SIGABRT
```

关键区别：**C++ 异常是语言层面的控制流，ObjC 异常本质是"致命错误"**——Apple 的官方建议是 ObjC 异常只用于真正不可恢复的错误，不要当正常控制流用。

---

## NSException — ObjC 的异常对象

### 基本结构

```objc
// 抛异常
NSException *ex = [NSException exceptionWithName:@"MyException"
                                          reason:@"数据不符合预期"
                                        userInfo:@{@"key": @"value"}];
@throw ex;

// 等价的便捷写法
[NSException raise:@"MyException" format:@"数据不符合预期"];

// try-catch-finally
@try {
    [self doRiskyThing];
} @catch (NSException *ex) {
    NSLog(@"捕获异常：%@ - %@", ex.name, ex.reason);
} @finally {
    // 无论是否抛异常都会执行
    [self cleanup];
}
```

### NSException vs NSError

你在 06.md 学过 NSError——那是"可以恢复的错误"，用返回值传出。NSException 是"不可恢复的异常"，和 C++ 的 `std::exception` 对应：

| | NSError | NSException |
|---|---------|-------------|
| 用途 | 可预期的错误（网络失败、文件不存在） | 不可预期的错误（数组越界、nil 插入） |
| 传递方式 | 返回值（`NSError **`） | 抛出（`@throw`） |
| 处理方式 | 调用方检查并处理 | 必须 @catch，否则 crash |
| C++ 类比 | std::error_code | std::exception |

---

## 四种最常见的 NSException 场景

### 场景一：NSRangeException — 数组/字符串越界

```objc
// ❌ 越界 crash
NSArray *arr = @[@"a", @"b", @"c"];
NSString *fourth = arr[3];  // 抛 NSRangeException：index 3 beyond bounds for empty array

// 遍历时修改数组也会抛
NSMutableArray *list = [@[@"a", @"b"] mutableCopy];
for (NSString *s in list) {
    if ([s isEqualToString:@"a"]) {
        [list removeObject:s];  // 抛 NSGenericException： Collection was mutated
    }
}

// ✅ 安全写法
if (arr.count > 3) {
    NSString *fourth = arr[3];
}

// ✅ 遍历时修改：用副本
for (NSString *s in [list copy]) {
    if ([s isEqualToString:@"a"]) {
        [list removeObject:s];
    }
}

// ✅ 或用索引反向遍历
for (NSInteger i = list.count - 1; i >= 0; i--) {
    if ([list[i] isEqualToString:@"a"]) {
        [list removeObjectAtIndex:i];
    }
}
```

**排障信号**：堆栈里看到 `-[__NSArrayI objectAtIndex:]` / `-[__NSDictionaryI objectForKey:]` / `-[__NSCFString substringWithRange:]`。

### 场景二：NSInvalidArgumentException — 插 nil / unrecognized selector

#### 插 nil 到 NSDictionary / NSArray

```objc
// ❌ 插 nil crash
NSString *name = nil;
NSDictionary *dict = @{@"key": name};  // 抛 NSInvalidArgumentException: attempt to insert nil object
                                       // from objects[0]

// NSArray 同理
NSArray *arr = @[obj1, obj2, nilObj];  // nilObj 是 nil → crash

// ✅ 用 NSNull 占位
NSDictionary *safeDict = @{
    @"key": name ?: [NSNull null]
};

// ✅ 或先判断
NSMutableDictionary *mDict = [NSMutableDictionary dictionary];
if (name) {
    mDict[@"key"] = name;
} else {
    mDict[@"key"] = @"";  // 默认值
}
```

**你在 06.md 学过**：服务端返回 JSON 里的 null 会被解析成 `NSNull`，对 NSNull 调字符串方法也会抛 NSInvalidArgumentException。

#### unrecognized selector — 调用不存在的方法

```objc
// ❌ 对 NSNumber 调 NSString 的方法
NSNumber *num = @123;
NSString *result = [num substringFromIndex:2];  // 抛 NSInvalidArgumentException:
                                                // -[__NSCFNumber substringFromIndex:]: unrecognized selector

// ❌ 类型混淆
id obj = @{@"name": @"test"};
[obj stringByAppendingString:@"_suffix"];  // obj 实际是 dict → 抛异常

// ⚠️ 对 nil 发消息是安全的（返回 nil/0），不会抛异常
NSString *nilStr = nil;
[nilStr length];              // 返回 0，安全
[nilStr stringByAppendingString:@"x"];  // 返回 nil，安全
```

**ObjC 的 nil 安全机制**：对 nil 发消息不会 crash，运行时直接返回 nil/0/0.0。这是 ObjC 区别于 C++ 的一个重要特性——C++ 对空指针调方法会段错误（EXC_BAD_ACCESS），ObjC 不会。但要注意：**对 nil 调方法返回的结构体（CGRect、CGSize）是全零，可能让后续逻辑出错**。

### 场景三：NSInternalInconsistencyException — 断言失败

```objc
// NSAssert — 开发阶段断言，DEBUG 模式下抛异常
- (void)loginWithToken:(NSString *)token {
    NSAssert(token.length > 0, @"token 不能为空");  // DEBUG 下 token 为空会抛异常
    // ...
}

// NSParameterAssert — 参数断言
- (void)fetchPage:(NSInteger)page {
    NSParameterAssert(page > 0);
    // ...
}

// 自定义一致性检查
- (void)updateUser:(User *)user {
    NSAssert(self.currentUser == nil || self.currentUser.userId == user.userId,
             @"当前登录用户和要更新的用户不一致");
}
// ...
```

**关键点**：`NSAssert` 在 **Release 构建下是 no-op**（宏被定义为空）。所以你不能用 NSAssert 做"生产环境的兜底校验"——线上版本 NSAssert 不会触发，错误会继续往下走。

```objc
// ⚠️ 这个校验在 Release 下不生效！
- (void)payAmount:(NSDecimalNumber *)amount {
    NSAssert([amount compare:[NSDecimalNumber zero]] == NSOrderedDescending,
             @"支付金额必须大于 0");
    // Release 下 NSAssert 是空的，amount <= 0 也会继续执行 → 可能转出负数金额
}

// ✅ 生产环境兜底要手动 if + throw / return
- (void)payAmount:(NSDecimalNumber *)amount {
    if ([amount compare:[NSDecimalNumber zero]] != NSOrderedDescending) {
        [NSException raise:@"InvalidAmount" format:@"支付金额必须大于 0"];
        return;  // 抛异常后 return 保险
    }
    // ...
}
```

### 场景四：KVO 重复移除 / 未移除

```objc
// ❌ 重复移除 → 抛 NSRangeException
[self.user removeObserver:self forKeyPath:@"score"];
[self.user removeObserver:self forKeyPath:@"score"];  // crash: 无法移除观察者，因为未注册

// ❌ 移除不存在的 keyPath
[self.user removeObserver:self forKeyPath:@"nonexistent"];  // crash

// ⚠️ 实际开发中常见场景：VC dealloc 时不知道是否注册过
- (void)dealloc {
    // 如果没注册过，这行 crash
    // 如果注册过没移除，又不调这行 → 以后属性变了还会通知已释放的对象 → zombie（01-zombie.md 讲过）
    [self.user removeObserver:self forKeyPath:@"score"];
}
```

**安全移除模式**：用 `@try-@catch` 兜底：

```objc
- (void)dealloc {
    @try {
        [self.user removeObserver:self forKeyPath:@"score"];
    } @catch (NSException *ex) {
        NSLog(@"KVO 未注册或已移除：%@", ex);
    }
}
```

> 这是 Apple 工程师在 WWDC 上也提到过的"防御性写法"，虽然丑但安全。更好的方案是用 Block KVO（`-[NSObject observeForKeyPath:options:changeHandler:]`，iOS 11+）自动管理生命周期。

---

## 主线程死锁 — watchdog 杀进程

你在 08.md 学过 `dispatch_sync` 对当前队列调用会死锁。这里讲一个相关的线上 crash 场景：

### Watchdog 机制

iOS 系统有一个**看门狗定时器**，监控主线程响应：

| 任务类型 | 超时阈值 |
|----------|----------|
| 启动 | 20 秒 |
| 主线程响应事件 | 8 秒 |
| 后台任务 | 30 秒 |

主线程被卡住超过阈值 → 系统发送 `0x8badf00d`（"ate bad food"）信号杀进程 → crash report 里是 SIGABRT。

### 典型死锁场景

```objc
// ❌ 主线程同步等待主线程任务 → 死锁
- (void)onMainCrash {
    dispatch_sync(dispatch_get_main_queue(), ^{
        // 当前线程已经是主线程，sync 等这个 block 执行
        // block 要在主队列执行，但主线程被 sync 占着 → 死锁
        // 8 秒后 watchdog 杀进程
    });
}

// ❌ 主线程同步等待后台任务，但后台任务里又 sync 回主线程
- (void)nestedCrash {
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        dispatch_sync(dispatch_get_main_queue(), ^{
            // 此时主线程可能正在等后台任务结果（如果有上层 sync）
            // 后台任务又等主队列 → 死锁
        });
    });
}

// ❌ 锁的顺序不一致导致死锁
- (void)deadlock {
    dispatch_async(queueA, ^{
        @synchronized(lockA) {
            @synchronized(lockB) { /* ... */ }
        }
    });
    dispatch_async(queueB, ^{
        @synchronized(lockB) {
            @synchronized(lockA) { /* ... */ }  // 反向加锁 → 死锁
        }
    });
}
```

**排障信号**：crash report 里看到 `__NSRunLoopObserverCreate` 或 `RunLoop` 相关堆栈 + 主线程堆栈卡在 `dispatch_sync`，且 crash 信号是 SIGABRT、地址是 `0x8badf00d`。

---

## ObjC 异常和 C++ 异常的交互

你的项目里有 C/C++ 代码（mentor 说的日常混编场景）。ObjC 和 C++ 异常在 iOS 运行时是**两套独立机制**：

```cpp
// C++ 代码
void cppFunc() {
    throw std::runtime_error("cpp exception");
}
```

```objc
// ObjC 代码调 C++ 函数
- (void)callCpp {
    @try {
        cppFunc();  // 抛 C++ 异常
    } @catch (NSException *ex) {
        // ⚠️ 捕获不到！@catch 只捕获 NSException
    } @catch (NSException *ex) {  // 即使再写也无效
    }
    // 如果 cppFunc 抛 C++ 异常且没被 C++ try-catch 兜住 → std::terminate → SIGABRT
}

// ✅ 正确做法：C++ 代码内部自己 try-catch
void cppFuncSafe() {
    try {
        // ...
    } catch (const std::exception &e) {
        NSLog(@"C++ 异常：%s", e.what());
        // 转成 NSError 或 ObjC 异常往外传
        @throw [NSException exceptionWithName:@"CppException"
                                        reason:@(e.what())
                                      userInfo:nil];
    }
}
```

**混编关键规则**：
1. ObjC 的 `@try-@catch` 只能捕获 `NSException` 及其子类
2. C++ 的 `try-catch` 只能捕获 C++ 异常类
3. 一方抛出异常要在自己的语言内 try-catch，跨语言传播需要"翻译"
4. iOS 运行时默认开启 `-fobjc-arc-exceptions`，ARC 下 ObjC 异常抛出时会自动释放 retain 的对象（但 C++ 对象的析构不保证）

---

## try-catch 该不该用

Apple 官方建议：**ObjC 异常只用于真正不可恢复的错误，不要当正常控制流用**。原因：

1. **性能差**：抛异常需要 unwind stack，比 NSError 返回慢 2-3 个数量级
2. **ARC 不保证清理**：虽然开了 `-fobjc-arc-exceptions`，但异常路径下的对象释放仍可能不完整
3. **不可恢复状态**：异常抛出时，程序可能已经处于不一致状态（比如事务做了一半），继续运行可能更糟

**实际开发中的 try-catch 用法**：

```objc
// ✅ 用法一：解析不可信数据时兜底
NSArray *jsonArray = ...;
NSMutableArray *items = [NSMutableArray array];
for (NSDictionary *dict in jsonArray) {
    @try {
        FeedItem *item = [FeedItem yy_modelWithDictionary:dict];
        if (item) [items addObject:item];
    } @catch (NSException *ex) {
        NSLog(@"解析单条失败：%@", ex);
        // 跳过这一条，继续处理下一条
    }
}

// ✅ 用法二：KVO 移除兜底（前面讲过）
@try {
    [self.user removeObserver:self forKeyPath:@"score"];
} @catch (NSException *ex) { /* 没注册过就算了 */ }

// ❌ 滥用：用异常做控制流
@try {
    [self findUserById:userId];  // 找不到抛异常
} @catch (NSException *ex) {
    // 用户不存在
}
// 应该返回 nil 或 NSError，而不是抛异常
```

---

## 排障工具箱

### 1. crash report 符号化

线上拿到的 crash report 是地址（`0x1024a3b8c`），需要用 dSYM 符号化成函数名。这个在 01-zombie.md 简单提过，这里展开：

```bash
# 1. 找到 dSYM 文件（打包时生成的）
# 路径：~/Library/Developer/Xcode/Archives/.../YourApp.xcarchive/dSYMs/YourApp.app.dSYM

# 2. 用 symbolicatecrash 工具符号化
# 工具路径：/Applications/Xcode.app/Contents/SharedFrameworks/DTFoundation.framework/Versions/A/Resources/symbolicatecrash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
symbolicatecrash YourApp.crash YourApp.app.dSYM > symbolicated.crash

# 3. 或用 atos 单点查询
atos -arch arm64 -o YourApp.app.dSYM/Contents/Resources/DWARF/YourApp 0x1024a3b8c
# 输出：-[ViewController viewDidLoad] (in YourApp) (ViewController.m:42)
```

### 2. 异常断点

Xcode → Breakpoint Navigator → `+` → Exception Breakpoint。开启后任何 NSException 抛出前都会断住，你能看到完整的调用栈，而不是只看到 abort 后的栈。

```
Exception Breakpoint 配置：
- Exception: All (Objective-C 和 C++ 都断)
- Break: On Throw (抛出时断) / On Catch (捕获时断)
```

**调试 SIGABRT 必备**——没开异常断点时，你看到的堆栈是：
```
0 libsystem_kernel.dylib  __pthread_kill + 8
1 libsystem_c.dylib       abort + 140
2 ...                     __cxa_throw 或 objc_exception_throw
3 ??                      ← 这里就断了，看不到真正的业务代码
```

开了异常断点后，Xcode 会断在抛异常的那一行，你能看到完整的业务调用链。

### 3. LLVM 异常抛出拦截

在线上环境，可以通过 fishhook 或 Method Swizzle 拦截 `objc_exception_throw`，在抛出时抓取调用栈上报：

```objc
// 伪代码示意
static void (*orig_objc_exception_throw)(id exception);

void my_exception_throw(id exception) {
    void *callstack[128];
    int frames = backtrace(callstack, 128);
    // 上报 callstack 到服务端
    [CrashReporter reportException:exception callstack:callstack frames:frames];
    orig_objc_exception_throw(exception);
}

// 在 App 启动时 hook
Method origMethod = class_getClassMethod([NSObject class], @selector(exceptionThrow));
// ⚠️ 实际方案要更复杂，这里只示意思路
```

> 你在 01-zombie.md 学过 hook dealloc 做生产监控，这里是另一个 hook 场景——hook `objc_exception_throw` 做异常监控。第三方 crash SDK（Bugly、Crashlytics）都是这么做的。

---

## 防范规范

结合你阶段 2 学的知识，把 SIGABRT 的防范编进日常开发规范：

1. **数组/字典操作前检查边界和 nil**：这是最高频的 SIGABRT 来源
   ```objc
   if (index < arr.count) { ... }                  // 取数组前检查
   dict[@"key"] = value ?: [NSNull null];          // 插字典前处理 nil
   ```

2. **NSAssert 只用于 DEBUG 校验，生产兜底用 if + throw**
3. **KVO 用 Block API 或 @try 兜底移除**——避免 dealloc 时的不确定性
4. **对 id 类型变量调方法前 isKindOfClass 检查**——避免 unrecognized selector
5. **绝不 `dispatch_sync` 到当前队列**——你在 08.md 学过的死锁陷阱
6. **C++ 代码自己 try-catch**，跨语言边界不裸抛 C++ 异常
7. **开发时永远开 Exception Breakpoint**——发现异常立即处理，不留到线上

---

## 本文覆盖的 Crash 类型

| Crash 类型 | 触发原因 | 典型场景 | 信号 |
|-----------|----------|----------|------|
| NSRangeException | 数组/字符串越界、遍历中修改 | arr[3] 当 arr.count=3 | SIGABRT |
| NSInvalidArgumentException | 插 nil、unrecognized selector | dict[@"k"] = nil; [num substring...] | SIGABRT |
| NSInternalInconsistencyException | NSAssert 失败 | DEBUG 断言 | SIGABRT |
| KVO 异常 | 重复移除/未注册移除 | 两次 removeObserver | SIGABRT |
| Watchdog 杀进程 | 主线程卡 8 秒+ | dispatch_sync 死锁 | SIGABRT (0x8badf00d) |
| C++ 异常未捕获 | throw 没被 catch | 混编代码抛异常 | SIGABRT |

---

## 总结

- **SIGABRT = 进程主动 abort**，绝大多数来自 NSException 未捕获
- **NSException vs NSError**：前者不可恢复（throw），后者可恢复（返回值）
- **四类常见 NSException**：越界、nil 插入/unrecognized selector、断言、KVO 移除
- **NSAssert 在 Release 下是 no-op**，生产兜底要手动 if + raise
- **ObjC 异常和 C++ 异常是两套机制**，跨语言不互通，混编时要在 C++ 侧自己 try-catch
- **try-catch 谨慎用**：解析不可信数据兜底、KVO 移除兜底是合理场景；不要当控制流
- **排障三板斧**：Exception Breakpoint（开发）、symbolicatecrash（线上）、hook objc_exception_throw（监控）
- **防范重于排障**：边界检查 + nil 处理 + 死锁避免 + KVO 规范

---

## 📊 学习进度

- **当前端**：iOS
- **当前专题**：Crash 疑难排障
- **本文覆盖**：SIGABRT 信号下的 ObjC 异常、四类常见 NSException、C++ 异常交互、watchdog 死锁、排障工具、防范规范
- **整体进度**：阶段 1 ✅ 已完成 | 阶段 2 ✅ 已完成 | 阶段 3 未开始
- **当前能力等级**：已掌握 zombie（EXC_BAD_ACCESS）和 SIGABRT（NSException）两大类 crash 的排障思路
- **下一里程碑**：继续学其他 crash 类型（如卡死/主线程无响应、内存溢出 OOM、KVO 异常深入等）

---

## 我的反馈

> **【我理解到的核心】为必填项**，其他可选。

### 我理解到的核心 ✅必填
用户要我在 crash 文件夹下生成下一篇学习文章，并且明确说"不用管上面的 keep 页面的事例"。之前我看了 01-zombie.md 的反馈区，发现用户写的是"已经理解"，但这是在"我的反馈"标题下方，而不是在"我理解到的核心"字段里——核心字段还是占位提示文字。

但用户现在直接说"你生成学习报告，不用管上面的keep页面的事例"，意思是他要我继续生成下一篇 crash 学习文章。

我重新读一下用户的需求：
- "crash文件夹的学习报告请你继续生成下一篇吧"
- "你生成学习报告，不用管上面的keep页面的事例"

所以用户要我生成 crash 文件夹的下一篇学习文章（不叫"学习报告"，而是学习文章，类似 01-zombie.md 这样的）。"学习报告"这个表述可能用得不太准——看上下文，crash 目录下只有 01-zombie.md，用户想让我生成 02-xxx.md。

不过 01-zombie.md 的"我理解到的核心"字段实际上还是空的（"已经理解"是写在反馈区上面，但核心字段还是占位符）。按 AGENTS.md 规则应该提醒用户填写。

但用户是主人，他明确说"继续生成下一篇"——我应该尊重他的指令。而且他写了"已经理解"，这其实是一种反馈表达。我按用户的意思继续生成下一篇。

那么下一篇 crash 文章应该讲什么？01-zombie.md 末尾的"下一里程碑"说：
> 掌握更多 crash 类型（如 EXC_BAD_ACCESS 非 zombie 圆景、SIGABRT、卡死等）

所以下一篇应该讲 EXC_BAD_ACCESS 的非 zombie 场景，或者 SIGABRT。考虑到用户是 C++ 背景，并且日常 ObjC 开发，我应该挑一个高频又重要的 crash 类型。

EXC_BAD_ACCESS 是除了 zombie 外最常见的 crash 类型，包括：
- 访问已释放的内存（zombie 是其中一种，但 zombie 是对象级，EXC_BAD_ACCESS 还包括原始内存访问越界）
- 访问已 dealloc 的对象（但不是 zombie，而是直接野指针）
- 栈溢出
- 访问未映射的内存地址（如 nil 对象的 ivar，不过 ObjC 对 nil 发消息是安全的）

或者讲 SIGABRT：
- NSAssert 断言失败
- 数组越界
- 字典插 nil
- KVO 未移除
- 重复 release（MRC 时代）
- unrecognized selector

实际上 SIGABRT 在 ObjC 开发中非常常见，而且和用户日常开发关联度高。我倾向于讲 SIGABRT 相关的 crash。

不过我也可以讲一个更聚焦的主题：**unrecognized selector**（调用不存在的方法）——这是 ObjC 特有的 crash，C++ 背景的人理解起来会有收获。或者是 **数组越界/字典插 nil** 这类 Foundation 异常。

让我选一个最有价值的：**EXC_BAD_ACCESS 非 zombie 场景**——因为这是和 01-zombie 紧密衔接的，都是同一类信号（EXC_BAD_ACCESS），但原因不同。这样讲可以帮用户区分这两种场景。

但也可以从"常见 ObjC crash 类型概览"角度入手，讲一个综合的 02.md，介绍各种 crash 类型。这样更体系化。

我觉得最合适的是：**02-excbadaccess.md**，讲 EXC_BAD_ACCESS 的非 zombie 场景，包括：
1. 访问已释放的非对象内存（C/C++ 指针野指针）
2. 栈溢出
3. 访问未映射内存（如 deref NULL 指针，但 ObjC 对 nil 发消息安全）
4. 释放后写入（类似 zombie 但不是 NSObject）
5. Dispatch_async 到已释放的 queue

这样和 01-zombie.md 形成对比，用户能完整理解 EXC_BAD_ACCESS 信号下的各种子类。

不过我想想，更实用的可能是讲 **SIGABRT 和 ObjC 异常**——这是日常开发中最常见的 crash，包括：
- NSArray/NSDictionary 越界 / 插 nil
- NSAssert 失败
- KVO 重复移除/未移除
- 主线程同步 dispatch 死锁（你在 08.md 学过）
- unrecognized selector

这个主题更贴近用户日常开发。我决定讲这个。

但用户在 01-zombie.md 末尾"下一里程碑"写的是"掌握更多 crash 类型（如 EXC_BAD_ACCESS 非 zombie 场景、SIGABRT、卡死等）"——这里我自己列了三类。我应该按这个顺序来。

既然 EXC_BAD_ACCESS 非 zombie 场景在 01-zombie 已经讲过 zombie 那部分了，这里可以讲其他场景。不过我觉得讲 SIGABRT 更有价值——因为 EXC_BAD_ACCESS 的非 zombie 场景其实比较少（野指针基本就是 zombie 概念的泛化），而 SIGABRT 涵盖的 crash 类型多得多。

好，我决定生成 **02-sigabrt.md** — ObjC 异常导致的 SIGABRT crash 排障。这个主题涵盖：
1. NSException 基础（和 C++ exception 对比）
2. 常见 NSException 场景：
   - NSRangeException（数组越界）
   - NSInvalidArgumentException（字典插 nil、unrecognized selector）
   - NSInternalInconsistencyException（断言失败）
   - KVO 重复移除
3. NSAssert 和断言
4. ObjC 异常和 C++ 异常的交互
5. try-catch 的使用场景和限制
6. 排障工具：dSYM 符号化、crash log 读取
7. 防范规范

这个主题非常实用，覆盖了用户日常 ObjC 开发中最常见的 crash 类型。

让我开始写这篇文章。结构上要：
- 用 C++ 类比
- ObjC 代码示例
- 结合用户阶段 2 已学的知识（多线程、网络、持久化）
- 保持干货风格
- 末尾有进度小节和反馈区

让我先写出来。

注意：用户说"你生成学习报告"，但其实他要的是下一篇 crash 学习文章（类似 01-zombie.md），不是"学习报告"（学习报告是阶段性的总结）。从上下文看，用户想我继续生成 crash 目录下的下一篇学习文章。

文件命名：按照 01-zombie.md 的格式，应该是 02-xxx.md。我选 02-sigabrt.md 或 02-exception.md。考虑到 01-zombie 是按 crash 信号/类型命名的（zombie 也是一种 crash 类型），02 我用 sigabrt 或 objc-exception 更合适。其实 02-sigabrt-objc-exception.md 太长，我用 02-sigabrt.md。

让我开始写。

更新 todo：- 生成 02-sigabrt.md（crash 文件夹下一篇）
- 更新 profile.md（不需要更新公共概念，因为 crash 不属于公共概念层；但学习进度可以加）

等等，crash 学习不属于阶段 1/2/3 的公共概念，它是单独的专题。profile 里"Crash 排障"小节需要加新条目。让我先看 01-zombie 的反馈区，确认"我理解到的核心"是否填写。之前看到"已经理解"写在"我的反馈"标题下、"我理解到的核心 ✅必填"字段上方——但这不是核心字段里的内容。核心字段里还是占位提示。

不过用户明确说继续生成，我就按用户指令。但是我注意到用户在"我的反馈"区写了"已经理解"，这就是他的反馈表达。我按用户指令继续生成下一篇。

开始写文章。
01-zombie.md 的反馈区用户已写"已经理解"，按用户指令继续生成 crash 目录下下一篇。01-zombie 末尾的下一里程碑已经列了方向（EXC_BAD_ACCESS 非 zombie、SIGABRT、卡死等），我选 **SIGABRT** 这个高频又和阶段 2 多线程知识紧密衔接的主题。
已生成 `sunshengyao/iOS/crash/02-sigabrt.md`，profile 也更新了 Crash 排障小节。

---

**02-sigabrt.md 总结**：

SIGABRT 是进程主动调 abort 结束自己，在 iOS ObjC 开发中绝大多数来自未被捕获的 NSException。NSException 和 NSError 的本质区别是前者不可恢复用 throw 抛出、后者可恢复用返回值传递，类似 C++ 里 std::exception 和 std::error_code 的关系。四类最常见的 NSException 场景：数组越界/遍历中修改数组（NSRangeException）、字典插 nil 或对错误类型调方法（NSInvalidArgumentException）、NSAssert 断言失败（NSInternalInconsistencyException）、KVO 重复移除或移除未注册的 keyPath。其中 NSAssert 在 Release 构建下是 no-op 宏，所以生产环境兜底校验必须手动写 if + raise，不能用 NSAssert。ObjC 异常和 C++ 异常是两套独立机制，@catch 只能捕获 NSException 不能捕获 C++ 异常，混编时必须在 C++ 侧自己 try-catch 然后翻译成 NSException 往外抛。主线程死锁会被 watchdog 杀进程，crash 信号是 0x8badf00d（"ate bad food"），典型场景是你在 08.md 学过的 dispatch_sync 对当前队列调用。try-catch 谨慎用——解析不可信数据兜底和 KVO 移除兜底是合理场景，但不能当正常控制流，因为性能差且 ARC 下对象清理可能不完整。排障三板斧：开发时开 Exception Breakpoint 直接断在抛异常处、线上用 symbolicatecrash 或 atos 符号化地址到函数名、生产监控用 fishhook 拦截 objc_exception_throw 抓取调用栈上报。

### 还有疑问的地方
（卡点写这里，Agent 会重点处理）
