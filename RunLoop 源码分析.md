# RunLoop 源码分析
此篇主要分析 RunLoop 的源码，对源码的注释在仓库中。
## 基础结构
### RunLoop 的基础结构
```
//RunLoop 对象结构
// 一个 RunLoop 主要包含了一个线程，当前线程所在的 mode，若干个commonmode，若干个 mode 等
struct __CFRunLoop {
    CFRuntimeBase _base;
    pthread_mutex_t _lock;			/* locked for accessing mode list */
    __CFPort _wakeUpPort;			// used for CFRunLoopWakeUp 内核向该端口发送消息可以唤醒 RunLoop
    Boolean _unused;                // 标志该 RunLoop 是否在使用
    volatile _per_run_data *_perRunData;              // reset for runs of the run loop
    pthread_t _pthread;                 //该 RunLoop 所在的线程
    uint32_t _winthread;
    CFMutableSetRef _commonModes;           // 记录 标记为common 的 RunLoopmode，存的是字符串
    CFMutableSetRef _commonModeItems;       // 存储所有 commonMode 的 item（input source，timer）
    CFRunLoopModeRef _currentMode;          // 当前 RunLoop 处于的 mode
    CFMutableSetRef _modes;                 // CFRunLoopModeRef
    struct _block_item *_blocks_head;
    struct _block_item *_blocks_tail;
    CFAbsoluteTime _runTime;
    CFAbsoluteTime _sleepTime;
    CFTypeRef _counterpart;
};
```
对于 RunLoop 结构，其中_pthread 表示该 RunLoop 所在的线程，_currentMode 表示当前 RunLoop 所处的模式。

在 RunLoop 中，有一个_commonModes变量，对于一个 RunLoop mode，它有一个标记位可以将自己标记为 common 类型的 mode。每当 RunLoop 中的内容发生变化时，RunLoop 都会自动将 _commonModeItems 里的 Source/Observer/Timer 同步到所有标记了 common 类型的 mode 里面去。

场景举例：主线程的 RunLoop 里有两个预置的 mode：kCFRunLoopDefaultMode，UITrackingRunLoopMode。这两个 mode 都是 common 类型的。DefaultMode 是 APP 日常所在的状态，TrackingRunLoopMode 是 scrollview 滑动时的状态，当创建一个 timer 然后将其添加到DefaultMode时，timer 会回调，但是如果滑动一个 tableview，RunLoop 的 mode 自动切换到UITrackingRunLoopMode，此时 timer 就会被停止。

如果需要 timer 在这两种 mode 里面都能正常调用，一种方式就是将 timer 分别加入到DefaultMode和TrackingRunLoopMode中。或者是将 timer 加入到 _commonModeItems 里面去，因为DefaultMode和TrackingRunLoopMode 都标记了 common 属性，所以 timer 会在滑动时自动更新到TrackingRunLoopMode中去。

### RunLoopMode 的结构
```
// RunLoopMode 结构体
// mode 负责管理在该 mode 下运行着的各种事件
struct __CFRunLoopMode {
    CFRuntimeBase _base;
    pthread_mutex_t _lock;	/* must have the run loop locked before locking this */
    CFStringRef _name;      //mode 名称
    Boolean _stopped;       //是否停止
    char _padding[3];
    // mode 内的几种事件类型
    CFMutableSetRef _sources0;
    CFMutableSetRef _sources1;
    CFMutableArrayRef _observers;
    CFMutableArrayRef _timers;
    CFMutableDictionaryRef _portToV1SourceMap;
    __CFPortSet _portSet;   //保证所有需要监听的 port 都在这个 set 里面
    CFIndex _observerMask;
#if USE_DISPATCH_SOURCE_FOR_TIMERS
    dispatch_source_t _timerSource;
    dispatch_queue_t _queue;
    Boolean _timerFired; // set to true by the source when a timer has fired
    Boolean _dispatchTimerArmed;
#endif
#if USE_MK_TIMER_TOO
    mach_port_t _timerPort;
    Boolean _mkTimerArmed;
#endif
#if DEPLOYMENT_TARGET_WINDOWS
    DWORD _msgQMask;
    void (*_msgPump)(void);
#endif
    uint64_t _timerSoftDeadline; /* TSR */
    uint64_t _timerHardDeadline; /* TSR */
};
```
RunLoopMode 对象有一个name，若干个 source0（Set类型），source1(Set类型)，observers(Array类型)，timers(Array类型)。下面分别介绍它们。
#### RunLoop Source
CFRunLoopSource是对input sources的抽象。CFRunLoopSource分source0和source1两个版本，它的结构如下：
```
//RunLoopmode 里面的几种事件类型
//有 source0 source1
struct __CFRunLoopSource {
    CFRuntimeBase _base;
    uint32_t _bits;
    pthread_mutex_t _lock;
    CFIndex _order;			/* immutable */
    CFMutableBagRef _runLoops;
    union {
	CFRunLoopSourceContext version0;	/* immutable, except invalidation */
        CFRunLoopSourceContext1 version1;	/* immutable, except invalidation */
    } _context;
};
```
source0 代表的是 APP 内部事件，如 UIEvent、CFSocket 都是 source0类型的。当一个 source0事件准备执行的时候，它必须是 signal 状态。
source1 是由 RunLoop 和内核管理的，可以接收内核消息并触发回调。

#### RunLoop observer
CFRunLoopObserver是观察者，可以观察RunLoop的各种状态，并抛出回调。
```
// 负责观察 RunLoop 处于的各种状态，并抛出回调
struct __CFRunLoopObserver {
    CFRuntimeBase _base;
    pthread_mutex_t _lock;
    CFRunLoopRef _runLoop;      // 观察的 RunLoop
    CFIndex _rlCount;
    CFOptionFlags _activities;		/* immutable */
    CFIndex _order;			/* immutable */
    CFRunLoopObserverCallBack _callout;	/* immutable */ // 抛出的回调
    CFRunLoopObserverContext _context;	/* immutable, except invalidation */
};
```
oberver 可以观察的状态如下：
```
/* Run Loop Observer Activities */
typedef CF_OPTIONS(CFOptionFlags, CFRunLoopActivity) {
    kCFRunLoopEntry = (1UL << 0), //即将进入run loop
    kCFRunLoopBeforeTimers = (1UL << 1), //即将处理timer
    kCFRunLoopBeforeSources = (1UL << 2),//即将处理source
    kCFRunLoopBeforeWaiting = (1UL << 5),//即将进入休眠
    kCFRunLoopAfterWaiting = (1UL << 6),//被唤醒但是还没开始处理事件
    kCFRunLoopExit = (1UL << 7),//run loop已经退出
    kCFRunLoopAllActivities = 0x0FFFFFFFU
};
```

#### CFRunLoopTimer
```
//定时器，可以在设定的时间点抛出回调
struct __CFRunLoopTimer {
    CFRuntimeBase _base;
    uint16_t _bits;         //标记是否 fire
    pthread_mutex_t _lock;
    CFRunLoopRef _runLoop;      // 添加了该 timer 的 RunLoop
    CFMutableSetRef _rlModes;   //存放着所有包含该 timer 的 mode 的 Modename，即一个 timer 可能被添加在多个 mode 上
    CFAbsoluteTime _nextFireDate;
    CFTimeInterval _interval;		/* immutable */  //时间间隔
    CFTimeInterval _tolerance;          /* mutable */ //时间偏差
    uint64_t _fireTSR;			/* TSR units */
    CFIndex _order;			/* immutable */
    CFRunLoopTimerCallBack _callout;	/* immutable */
    CFRunLoopTimerContext _context;	/* immutable, except invalidation */
};
```
根据官方说明，CFRunLoopTimer 和 NSTimer 是可以互相转换的。

以上，即是介绍了 RunLoop 及其相关的类型的数据结构，从结构中我们可以看出 RunLoop 的内部结构大致类似这样：
![RunLoop 内部结构]()

### RunLoop 是如何创建的？
对于开发者，苹果不允许直接创建 RunLoop 对象，只能通过函数获取 RunLoop：
* CFRunLoopRef CFRunLoopGetCurrent(void)
* CFRunLoopRef CFRunLoopGetMain(void)
* +(NSRunLoop *)currentRunLoop
* +(NSRunLoop *)currentRunLoop
下面两个是 cocoa 框架中的。
那么，在源码中 RunLoop 是什么时候被创建的呢？我们从CFRunLoopGetCurrent和CFRunLoopGetMain这两个获取 RunLoop 的方法中探寻端倪。
#### CFRunLoopGetCurrent
```
//此方法用于获取当前的 RunLoop 对象
CFRunLoopRef CFRunLoopGetCurrent(void) {
    CHECK_FOR_FORK();
    CFRunLoopRef rl = (CFRunLoopRef)_CFGetTSD(__CFTSDKeyRunLoop);
    if (rl) return rl;
    //传入当前线程 必须要在线程内部才能获取到当前线程
    return _CFRunLoopGet0(pthread_self());
}
```
可以看到，在 CFRunLoopGetCurrent 函数内部调用了_CFRunLoopGet0()，传入的是当前的线程。这里可以看出 CFRunLoopGetCurrent 必须要在线程内部调用，才能获取到当前线程的 RunLoop。即子线程的 RunLoop 必须在子线程内部获取。

#### CFRunLoopGetMain
```
//获取主线程 RunLoop
CFRunLoopRef CFRunLoopGetMain(void) {
    CHECK_FOR_FORK();
    static CFRunLoopRef __main = NULL; // no retain needed
    //传入的是主线程，无论是在子线程还是主线程，都可以调用该方法获得主线程
    if (!__main) __main = _CFRunLoopGet0(pthread_main_thread_np()); // no CAS needed
    return __main;
}
```
在 CFRunLoopGetMain 方法中，与 CFRunLoopGetCurrent 不同的是 CFRunLoopGet0 方法中传入的是主线程，由此可以看出，不论是在主线程还是子线程中调用，都可以获取到主线程的 RunLoop。

既然不管是 CFRunLoopGetMain 还是 CFRunLoopGetCurrent 方法都是通过调用 CFRunLoopGet0 这个方法去获得线程的，那么我们就去这个函数内部观察一下是如何得到 RunLoop 的。
#### CFRunLoopGet0 方法
```
// 根据传入的线程 t 返回 RunLoop 对象
CF_EXPORT CFRunLoopRef _CFRunLoopGet0(pthread_t t) {
    if (pthread_equal(t, kNilPthreadT)) {
	t = pthread_main_thread_np();
    }
    __CFLock(&loopsLock);
    // 如果CFMutableDictionaryRef __CFRunLoops为空，则需要构建一个 字典
    if (!__CFRunLoops) {
        __CFUnlock(&loopsLock);
        //创建一个字典
	CFMutableDictionaryRef dict = CFDictionaryCreateMutable(kCFAllocatorSystemDefault, 0, NULL, &kCFTypeDictionaryValueCallBacks);
    // 创建一个主线程的 RunLoop
	CFRunLoopRef mainLoop = __CFRunLoopCreate(pthread_main_thread_np());
    // 将主线程的 mainloop 保存到字典中， key 是线程，value 是 RunLoop
	CFDictionarySetValue(dict, pthreadPointer(pthread_main_thread_np()), mainLoop);
    //写入到__CFRunLoops
	if (!OSAtomicCompareAndSwapPtrBarrier(NULL, dict, (void * volatile *)&__CFRunLoops)) {
	    CFRelease(dict);
	}
    //释放 mainrunloop
	CFRelease(mainLoop);
        __CFLock(&loopsLock);
    }
    // 在第一次进入时，不论传进来的是 主线程还是子线程，总是先去主线程的 RunLoop
    // 从字典__CFRunLoops中获取传入线程t 的RunLoop
    CFRunLoopRef loop = (CFRunLoopRef)CFDictionaryGetValue(__CFRunLoops, pthreadPointer(t));
    __CFUnlock(&loopsLock);
    // 没获取到
    if (!loop) {
        //根据线程t 创建一个 RunLoop
	CFRunLoopRef newLoop = __CFRunLoopCreate(t);
        __CFLock(&loopsLock);
	loop = (CFRunLoopRef)CFDictionaryGetValue(__CFRunLoops, pthreadPointer(t));
	if (!loop) {
        // 把创建的RunLoop 放入__CFRunLoops，key 是线程
	    CFDictionarySetValue(__CFRunLoops, pthreadPointer(t), newLoop);
	    loop = newLoop;
	}
        // don't release run loops inside the loopsLock, because CFRunLoopDeallocate may end up taking it
        __CFUnlock(&loopsLock);
	CFRelease(newLoop);
    }
    // 如果传入的线程就是当前线程
    if (pthread_equal(t, pthread_self())) {
        _CFSetTSD(__CFTSDKeyRunLoop, (void *)loop, NULL);
        if (0 == _CFGetTSD(__CFTSDKeyRunLoopCntr)) {
            //注册回调 ，在线程销毁时，销毁对应的 RunLoop
            _CFSetTSD(__CFTSDKeyRunLoopCntr, (void *)(PTHREAD_DESTRUCTOR_ITERATIONS-1), (void (*)(void *))__CFFinalizeRunLoop);
        }
    }
    return loop;
}
```
