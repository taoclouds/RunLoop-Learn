# RunLoop 源码分析
此篇主要分析 RunLoop 的源码，对源码的注释在仓库中。

分析源码我主要采用的是：

RunLoop 相关的结构 -> RunLoop 如何创建 -> RunLoop 如何运行 这样的路径来分析的。
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
![RunLoop 内部结构](https://github.com/taoclouds/RunLoop-Learn/blob/master/image/runloop%E7%BB%93%E6%9E%84.png?raw=true)

## RunLoop 如何创建
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
// t==0 is a synonym for "main thread" that always works
// 根据传入的线程 t 返回 RunLoop 对象
CF_EXPORT CFRunLoopRef _CFRunLoopGet0(pthread_t t) {
    // 如果  线程t 是 nil，则获取主线程
    if (pthread_equal(t, kNilPthreadT)) {
	t = pthread_main_thread_np();
    }
    __CFLock(&loopsLock);
    //  __CFRunLoops为一个字典，它存储着 RunLoop 与线程。存储方式是key 为线程，value 是 RunLoop
    //  如果__CFRunLoops为空，则需要构建一个 字典来填充一下
    if (!__CFRunLoops) {
        __CFUnlock(&loopsLock);
        //创建一个字典
	CFMutableDictionaryRef dict = CFDictionaryCreateMutable(kCFAllocatorSystemDefault, 0, NULL, &kCFTypeDictionaryValueCallBacks);
    // 创建一个主线程的 RunLoop
	CFRunLoopRef mainLoop = __CFRunLoopCreate(pthread_main_thread_np());
    // 将主线程的 mainloop 保存到字典中， key 是线程，value 是  main RunLoop
	CFDictionarySetValue(dict, pthreadPointer(pthread_main_thread_np()), mainLoop);
    //写入到__CFRunLoops
	if (!OSAtomicCompareAndSwapPtrBarrier(NULL, dict, (void * volatile *)&__CFRunLoops)) {
	    CFRelease(dict);
	}
    //释放 mainrunloop
	CFRelease(mainLoop);
        __CFLock(&loopsLock);
    }
    // 在第一次进入时，不论传进来的是 主线程还是子线程，总是先取得主线程的 RunLoop
    // 从字典__CFRunLoops中获取传入线程t 的RunLoop
    CFRunLoopRef loop = (CFRunLoopRef)CFDictionaryGetValue(__CFRunLoops, pthreadPointer(t));
    __CFUnlock(&loopsLock);
    // 没获取到
    if (!loop) {
        //根据线程t 创建一个 RunLoop
	CFRunLoopRef newLoop = __CFRunLoopCreate(t);
        __CFLock(&loopsLock);
        // 再取一遍难道不还是空吗？
	loop = (CFRunLoopRef)CFDictionaryGetValue(__CFRunLoops, pthreadPointer(t));
	if (!loop) {
        // 把创建的RunLoop newLoop 放入__CFRunLoops，key 是线程
	    CFDictionarySetValue(__CFRunLoops, pthreadPointer(t), newLoop);
	    loop = newLoop;
	}
        // don't release run loops inside the loopsLock, because CFRunLoopDeallocate may end up taking it
        __CFUnlock(&loopsLock);
        //释放创建的 newLoop
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
通过源码可以看到，CFRunLoopGet0 方法不论传入的是主线程还是子线程，如果 __CFRunLoops 是空，则取得主线程 RunLoop并存到__CFRunLoops中去，key 是线程，value 是  main RunLoop。接下来从字典__CFRunLoops中获取传入线程t 的RunLoop，如果没有获取到，那么就根据线程t 创建一个 RunLoop。然后把创建的RunLoop newLoop 放入__CFRunLoops中。RunLoop 会在线程销毁时销毁。

同时，我们可以确定 RunLoop 与线程一一对应的方式是通过全局字典来实现的。主线程的 RunLoop 在初始化全局字典时就会创建，子线程的 RunLoop 会在第一次获取时创建，如果没获取就根据线程尝试创建一个 RunLoop。

在上面的源码中 newLoop 是__CFRunLoopCreate这个方法创建返回的，从函数名也可以看出，我们终于抓住了创建 RunLoop 的方法了，接下来去__CFRunLoopCreate 这个方法中看看是如何创建 RunLoop 的。

#### __CFRunLoopCreate 方法
```
// 根据传进来的线程t 创建对应的 RunLoop
static CFRunLoopRef __CFRunLoopCreate(pthread_t t) {
    // d 定义一个 RunLoop 和对应的 mode
    CFRunLoopRef loop = NULL;
    CFRunLoopModeRef rlm;
    //初始化分配空间
    uint32_t size = sizeof(struct __CFRunLoop) - sizeof(CFRuntimeBase);
    loop = (CFRunLoopRef)_CFRuntimeCreateInstance(kCFAllocatorSystemDefault, CFRunLoopGetTypeID(), size, NULL);
    if (NULL == loop) {
        //创建失败，空间不够
	return NULL;
    }
    // 继续初始化一些参数
    (void)__CFRunLoopPushPerRunData(loop);
    __CFRunLoopLockInit(&loop->_lock);
    loop->_wakeUpPort = __CFPortAllocate();
    if (CFPORT_NULL == loop->_wakeUpPort) HALT;
    __CFRunLoopSetIgnoreWakeUps(loop);
    //设置 RunLoop 的 commonModes
    loop->_commonModes = CFSetCreateMutable(kCFAllocatorSystemDefault, 0, &kCFTypeSetCallBacks);
    CFSetAddValue(loop->_commonModes, kCFRunLoopDefaultMode);
    loop->_commonModeItems = NULL;
    loop->_currentMode = NULL;
    loop->_modes = CFSetCreateMutable(kCFAllocatorSystemDefault, 0, &kCFTypeSetCallBacks);
    loop->_blocks_head = NULL;
    loop->_blocks_tail = NULL;
    loop->_counterpart = NULL;
    loop->_pthread = t;
#if DEPLOYMENT_TARGET_WINDOWS
    loop->_winthread = GetCurrentThreadId();
#else
    loop->_winthread = 0;
#endif
    rlm = __CFRunLoopFindMode(loop, kCFRunLoopDefaultMode, true);
    if (NULL != rlm) __CFRunLoopModeUnlock(rlm);
    return loop;
}
```
从源码可以看到初始化 RunLoop 时需要分配一定的内存空间，并且初始化一些相关的参数。包括使用CFSetCreateMutable函数设置 RunLoop 的_commonModes。
现在我们找到了 RunLoop 的创建函数，知道了RunLoop 是如何创建的。但是还有一个问题，在创建 RunLoop 时，RunLoop 对应的 mode 是如何创建的呢？

### RunLoopMode 是如何创建的

针对 Mode 的操作，苹果只开放了以下3个 API 来操作 Mode:
* CFRunLoopAddCommonMode(CFRunLoopRef rl, CFStringRef mode) 向当前 RunLoop 的 common modes 中添加一个 mode。
* CFStringRef CFRunLoopCopyCurrentMode(CFRunLoopRef rl)  返回当前运行的 mode 的名称
* CFArrayRef CFRunLoopCopyAllModes(CFRunLoopRef rl)   返回当前 RunLoop 的所有 mode。
#### CFRunLoopAddCommonMode 函数

对于开发者，没有办法直接创建一个 CFRunLoopMode 对象，但是可以调用 CFRunLoopAddCommonMode 传入一个字符串向 RunLoop 中添加 mode，传入的字符串即为 mode 的名称，我们也是利用通过 mode 的 name 来操作 RunLoopMode 的。还是直接看源码：
```
// 根据 RunLoop rl 和 mode name 创建对于的 mode
void CFRunLoopAddCommonMode(CFRunLoopRef rl, CFStringRef modeName) {
    CHECK_FOR_FORK();
    if (__CFRunLoopIsDeallocating(rl)) return;
    __CFRunLoopLock(rl);
    if (!CFSetContainsValue(rl->_commonModes, modeName)) {
	CFSetRef set = rl->_commonModeItems ? CFSetCreateCopy(kCFAllocatorSystemDefault, rl->_commonModeItems) : NULL;
	CFSetAddValue(rl->_commonModes, modeName);
	if (NULL != set) {
	    CFTypeRef context[2] = {rl, modeName};
	    /* add all common-modes items to new mode */
	    CFSetApplyFunction(set, (__CFRunLoopAddItemsToCommonMode), (void *)context);
	    CFRelease(set);
	}
    } else {
    }
    __CFRunLoopUnlock(rl);
}
```
以上源码说明 RunLoop 通过 modeName 来管理 mode。modeName 不能重复，modeName 是 mode 的唯一标识。RunLoop的_commonModes数组存放所有被标记为common的mode的名称。
添加commonMode会把commonModeItems数组中的所有source同步到新添加的mode中。CFRunLoopMode对象在CFRunLoopAddItemsToCommonMode函数中调用CFRunLoopFindMode时被创建。

#### CFRunLoopCopyCurrentMode 函数
```
CFStringRef CFRunLoopCopyCurrentMode(CFRunLoopRef rl) {
    CHECK_FOR_FORK();
    CFStringRef result = NULL;
    __CFRunLoopLock(rl);
    if (NULL != rl->_currentMode) {
	result = (CFStringRef)CFRetain(rl->_currentMode->_name);
    }
    __CFRunLoopUnlock(rl);
    return result;
}
```
直接返回当前 mode 的名称： rl->_currentMode->_name

#### CFRunLoopCopyAllModes 函数
```
CFArrayRef CFRunLoopCopyAllModes(CFRunLoopRef rl) {
    CHECK_FOR_FORK();
    CFMutableArrayRef array;
    __CFRunLoopLock(rl);
    array = CFArrayCreateMutable(kCFAllocatorSystemDefault, CFSetGetCount(rl->_modes), &kCFTypeArrayCallBacks);
    CFSetApplyFunction(rl->_modes, (__CFRunLoopGetModeName), array);
    __CFRunLoopUnlock(rl);
    return array;
}
```
CFRunLoopCopyAllModes 函数返回RunLoop 的所有 mode，是一个数组 Array。

在之前的介绍中，除了添加 Mode 到 RunLoop 中，还需要往 mode 中添加 source，observer 和 timer。添加这些到 mode 中的源码分析如下。

### RunLoop 添加 source/timer/observer
下面以添加 source 为例，分析 是如何向 RunLoopMode 中添加 source 的。
#### 添加 RunLoop Source
```
// 向 RunLoop 中添加 source 事件
void CFRunLoopAddSource(CFRunLoopRef rl, CFRunLoopSourceRef rls, CFStringRef modeName) {	/* DOES CALLOUT */
    CHECK_FOR_FORK();
    if (__CFRunLoopIsDeallocating(rl)) return;
    if (!__CFIsValid(rls)) return;
    Boolean doVer0Callout = false;
    __CFRunLoopLock(rl);
    // 如果是 commonmode
    if (modeName == kCFRunLoopCommonModes) {
        //将 commonmode copy 一份赋值给 set
	CFSetRef set = rl->_commonModes ? CFSetCreateCopy(kCFAllocatorSystemDefault, rl->_commonModes) : NULL;
	if (NULL == rl->_commonModeItems) {
        // rl里面的 item 为空，则初始化一个
	    rl->_commonModeItems = CFSetCreateMutable(kCFAllocatorSystemDefault, 0, &kCFTypeSetCallBacks);
	}
    // 将传入的 source 加入到 commonModeitem 里面
	CFSetAddValue(rl->_commonModeItems, rls);
    // 如果刚才 set 里面有数据
	if (NULL != set) {
	    CFTypeRef context[2] = {rl, rls};
	    /* add new item to all common-modes */
	    CFSetApplyFunction(set, (__CFRunLoopAddItemToCommonModes), (void *)context);
	    CFRelease(set);
	}
    } else {
        // 如果不是 commonmode 则根据 modename 查找一下 mode
	CFRunLoopModeRef rlm = __CFRunLoopFindMode(rl, modeName, true);
    //如果 mode 没找到或者 source0没找到 则初始化 source0等
	if (NULL != rlm && NULL == rlm->_sources0) {
	    rlm->_sources0 = CFSetCreateMutable(kCFAllocatorSystemDefault, 0, &kCFTypeSetCallBacks);
	    rlm->_sources1 = CFSetCreateMutable(kCFAllocatorSystemDefault, 0, &kCFTypeSetCallBacks);
	    rlm->_portToV1SourceMap = CFDictionaryCreateMutable(kCFAllocatorSystemDefault, 0, NULL, NULL);
	}

    // 如果 source0和 source1中都不包含传入的 source
	if (NULL != rlm && !CFSetContainsValue(rlm->_sources0, rls) && !CFSetContainsValue(rlm->_sources1, rls)) {
	    if (0 == rls->_context.version0.version) {
            //版本是0， 添加到 source0
	        CFSetAddValue(rlm->_sources0, rls);
	    } else if (1 == rls->_context.version0.version) {
            //版本为1 ，添加到 source1
	        CFSetAddValue(rlm->_sources1, rls);
		__CFPort src_port = rls->_context.version1.getPort(rls->_context.version1.info);
		if (CFPORT_NULL != src_port) {
            // 在 source1的时候讲传入的 source 和一个 mach_port_t绑定
		    CFDictionarySetValue(rlm->_portToV1SourceMap, (const void *)(uintptr_t)src_port, rls);
		    __CFPortSetInsert(src_port, rlm->_portSet);
	        }
	    }
	    __CFRunLoopSourceLock(rls);
        // 添加 RunLoop 到 source 的 RunLoops 中
	    if (NULL == rls->_runLoops) {
	        rls->_runLoops = CFBagCreateMutable(kCFAllocatorSystemDefault, 0, &kCFTypeBagCallBacks); // sources retain run loops!
	    }
	    CFBagAddValue(rls->_runLoops, rl);
	    __CFRunLoopSourceUnlock(rls);
	    if (0 == rls->_context.version0.version) {
	        if (NULL != rls->_context.version0.schedule) {
	            doVer0Callout = true;
	        }
	    }
	}
        if (NULL != rlm) {
	    __CFRunLoopModeUnlock(rlm);
	}
    }
    __CFRunLoopUnlock(rl);
    if (doVer0Callout) {
        // although it looses some protection for the source, we have no choice but
        // to do this after unlocking the run loop and mode locks, to avoid deadlocks
        // where the source wants to take a lock which is already held in another
        // thread which is itself waiting for a run loop/mode lock
	rls->_context.version0.schedule(rls->_context.version0.info, rl, modeName);	/* CALLOUT */
    }
}
```
之前提到过，commonModes 是一个特殊的模式，标记为 common 类型的 mode。每当 RunLoop 中的内容发生变化时，RunLoop 都会自动将 _commonModeItems 里的 Source/Observer/Timer 同步到所有标记了 common 类型的 mode 里面去。
这点体现在源码里`CFSetRef set = rl->_commonModes ? CFSetCreateCopy(kCFAllocatorSystemDefault, rl->_commonModes) : NULL;`，如果 modeName 为 kCFRunLoopCommonModes 类型的。然后将 set 里面的内容添加到 commonModeitem 里面。在添加 source 的时候需要判断一下 source 版本，确定是添加到 source0 还是 source1 。

#### 添加 observer 和 timer

添加observer和timer的内部逻辑和添加source大体类似。

区别在于observer和timer只能被添加到一个RunLoop的一个或者多个mode中，比如一个timer被添加到主线程的RunLoop中，则不能再把该timer添加到子线程的RunLoop，而source没有这个限制，不管是哪个RunLoop，只要mode中没有，就可以添加。

正如一开始的基础结构所示：CFRunLoopSource结构体中有保存RunLoop对象的数组，而CFRunLoopObserver和CFRunLoopTimer只有单个RunLoop对象。

## RunLoop 是如何运行的？
在 RunLoop 的运行，在 Core Foundation 中可以通过以下两个 API 运行 RunLoop：
* CFRunLoopRun(void) 在默认的 mode 下运行当前线程的 RunLoop。
* CFRunLoopRunInMode(CFStringRef mode, CFTimeInterval seconds, Boolean returnAfterSourceHandled)   在指定的 mode 下运行当前线程的 RunLoop。
对于 RunLoop，它的运行过程如下：
[RunLoop 运行过程]()
下面通过源码来分析 RunLoop 的运行。
首先是 CFRunLoopRun 和 CFRunLoopRunInMode。它们是在 RunLoop 运行时会调用的函数：
```
//RunLoop 运行
void CFRunLoopRun(void) {	/* DOES CALLOUT */
    int32_t result;
    do {
        // 传入当前 RunLoop，mode 是 defaultmode。
        result = CFRunLoopRunSpecific(CFRunLoopGetCurrent(), kCFRunLoopDefaultMode, 1.0e10, false);
        CHECK_FOR_FORK();
    } while (kCFRunLoopRunStopped != result && kCFRunLoopRunFinished != result);
}

SInt32 CFRunLoopRunInMode(CFStringRef modeName, CFTimeInterval seconds, Boolean returnAfterSourceHandled) {     /* DOES CALLOUT */
    CHECK_FOR_FORK();
    return CFRunLoopRunSpecific(CFRunLoopGetCurrent(), modeName, seconds, returnAfterSourceHandled);
}
```
在这两个方法中，实际都调用了 CFRunLoopRunSpecific 这个方法。这个方法中包括了对 RunLoop 的运行过程的解释：

```
// 传入 RunLoop 和 mode
SInt32 CFRunLoopRunSpecific(CFRunLoopRef rl, CFStringRef modeName, CFTimeInterval seconds, Boolean returnAfterSourceHandled) {     /* DOES CALLOUT */
    CHECK_FOR_FORK();
    // 如果 RunLoop 不存在，直接返回
    if (__CFRunLoopIsDeallocating(rl)) return kCFRunLoopRunFinished;
    __CFRunLoopLock(rl);
    // 根据 modename 找到当前RunLoop 的 mode => currentmode
    CFRunLoopModeRef currentMode = __CFRunLoopFindMode(rl, modeName, false);
    // 如果没找到，currentmode 为 null 或者 mode 中没有任何事件，则返回
    if (NULL == currentMode || __CFRunLoopModeIsEmpty(rl, currentMode, rl->_currentMode)) {
	Boolean did = false;
	if (currentMode) __CFRunLoopModeUnlock(currentMode);
	__CFRunLoopUnlock(rl);
	return did ? kCFRunLoopRunHandledSource : kCFRunLoopRunFinished;
    }
    //volatile 修饰表示 _per_run_data 随时都有可能改变
    volatile _per_run_data *previousPerRun = __CFRunLoopPushPerRunData(rl);
    // 使用previousMode 记录之前运行时的 mode
    CFRunLoopModeRef previousMode = rl->_currentMode;
    // 将找到的 currentmode 赋值给 RunLoop 的 currentmode。
    rl->_currentMode = currentMode;
    // 初始化 result 表示 RunLoop 运行结束
    int32_t result = kCFRunLoopRunFinished;

    // runloop 运行前检查是否有 observer 在监听
	if (currentMode->_observerMask & kCFRunLoopEntry ) __CFRunLoopDoObservers(rl, currentMode, kCFRunLoopEntry);
	result = __CFRunLoopRun(rl, currentMode, seconds, returnAfterSourceHandled, previousMode);
    // RunLoop 退出运行后检查是否有 observer 在监听
	if (currentMode->_observerMask & kCFRunLoopExit ) __CFRunLoopDoObservers(rl, currentMode, kCFRunLoopExit);

        __CFRunLoopModeUnlock(currentMode);
        __CFRunLoopPopPerRunData(rl, previousPerRun);
	rl->_currentMode = previousMode;
    __CFRunLoopUnlock(rl);
    return result;
}
```
CFRunLoopRunSpecific 这个函数接收 RunLoop 和一个RunLoop 运行时的模式 modeName，在这个函数中，我们可以通过与之前的那张 RunLoop 运行图来对应，RunLoop 的真正运行是在 __CFRunLoopRun 这个函数中发生的，在调用 __CFRunLoopRun 函数前，通过 __CFRunLoopDoObservers 监听 observer，并且在 RunLoop 退出后，仍然检查是否有 observer 更新。
下面是 __CFRunLoopRun 这个函数。这个函数比较长，所以我看的也比较迷糊，就大致看了下与上面的 RunLoop 运行过程图对应一下：
```
// RunLoop 运行时执行的函数
/*
* rl：RunLoop 对象
* rlm: RunLoop  当前的mode
* seconds: 时间
* stopAfterHandle：处理完是否停止
* previousMode：RunLoop 之前的 mode
*/
static int32_t __CFRunLoopRun(CFRunLoopRef rl, CFRunLoopModeRef rlm, CFTimeInterval seconds, Boolean stopAfterHandle, CFRunLoopModeRef previousMode) {
    // 记录开始时间，主要是用于控制超时
    uint64_t startTSR = mach_absolute_time();

    // 如果 rl 已经停止，直接返回
    if (__CFRunLoopIsStopped(rl)) {
        __CFRunLoopUnsetStopped(rl);
	return kCFRunLoopRunStopped;
    } else if (rlm->_stopped) {
        // 如果 rlm 是 stop 状态，也直接返回
	rlm->_stopped = false;
	return kCFRunLoopRunStopped;
    }
    // 标记 mach 端口
    mach_port_name_t dispatchPort = MACH_PORT_NULL;
    // libdispatchQSafe 标记是否是主线程
    Boolean libdispatchQSafe = pthread_main_np() && ((HANDLE_DISPATCH_ON_BASE_INVOCATION_ONLY && NULL == previousMode) || (!HANDLE_DISPATCH_ON_BASE_INVOCATION_ONLY && 0 == _CFGetTSD(__CFTSDKeyIsInGCDMainQ)));

    // libdispatchQSafe && RunLoop 是不是主线程的 RunLoop && 该 mode 是不是 commonmode。
    // 是的话获取到主线程的 port
    if (libdispatchQSafe && (CFRunLoopGetMain() == rl) && CFSetContainsValue(rl->_commonModes, rlm->_name)) dispatchPort = _dispatch_get_main_queue_port_4CF();

#if USE_DISPATCH_SOURCE_FOR_TIMERS
    mach_port_name_t modeQueuePort = MACH_PORT_NULL;

    // 如果 mode 队列不为空
    if (rlm->_queue) {
        // 获取 port，为空直接 crash
        modeQueuePort = _dispatch_runloop_root_queue_get_port_4CF(rlm->_queue);
        if (!modeQueuePort) {
            CRASH("Unable to get port for run loop mode queue (%d)", -1);
        }
    }
#endif
    // 定时器，用于实现 RunLoop 超时机制
    dispatch_source_t timeout_timer = NULL;
    // 设置超时的 context
    struct __timeout_context *timeout_context = (struct __timeout_context *)malloc(sizeof(*timeout_context));
    if (seconds <= 0.0) { // instant timeout
        // 超时
        seconds = 0.0;
        timeout_context->termTSR = 0ULL;
    } else if (seconds <= TIMER_INTERVAL_LIMIT) {
        // 超时时执行__CFRunLoopTimeout函数。
	dispatch_queue_t queue = pthread_main_np() ? __CFDispatchQueueGetGenericMatchingMain() : __CFDispatchQueueGetGenericBackground();
	timeout_timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
        dispatch_retain(timeout_timer);
	timeout_context->ds = timeout_timer;
	timeout_context->rl = (CFRunLoopRef)CFRetain(rl);
	timeout_context->termTSR = startTSR + __CFTimeIntervalToTSR(seconds);
	dispatch_set_context(timeout_timer, timeout_context); // source gets ownership of context
	dispatch_source_set_event_handler_f(timeout_timer, __CFRunLoopTimeout);
        dispatch_source_set_cancel_handler_f(timeout_timer, __CFRunLoopTimeoutCancel);
        uint64_t ns_at = (uint64_t)((__CFTSRToTimeInterval(startTSR) + seconds) * 1000000000ULL);
        dispatch_source_set_timer(timeout_timer, dispatch_time(1, ns_at), DISPATCH_TIME_FOREVER, 1000ULL);
        dispatch_resume(timeout_timer);
    } else { // infinite timeout
        //永远不会超时
        seconds = 9999999999.0;
        timeout_context->termTSR = UINT64_MAX;
    }

    // 标志位置位 true
    Boolean didDispatchPortLastTime = true;
    // 记录下 RunLoop 的状态
    int32_t retVal = 0;
    do {
#if DEPLOYMENT_TARGET_MACOSX || DEPLOYMENT_TARGET_EMBEDDED || DEPLOYMENT_TARGET_EMBEDDED_MINI
        voucher_mach_msg_state_t voucherState = VOUCHER_MACH_MSG_STATE_UNCHANGED;
        voucher_t voucherCopy = NULL;
#endif


// 初始化一个存放内核消息的缓冲池
        uint8_t msg_buffer[3 * 1024];
#if DEPLOYMENT_TARGET_MACOSX || DEPLOYMENT_TARGET_EMBEDDED || DEPLOYMENT_TARGET_EMBEDDED_MINI
        mach_msg_header_t *msg = NULL;
        mach_port_t livePort = MACH_PORT_NULL;
#elif DEPLOYMENT_TARGET_WINDOWS
        HANDLE livePort = NULL;
        Boolean windowsMessageReceived = false;
#endif
// 取得需要监听的 port
	__CFPortSet waitSet = rlm->_portSet;
    // 设置该 RunLoop rl 可以被唤醒
        __CFRunLoopUnsetIgnoreWakeUps(rl);

        // 通知 observer ， 即将触发 timer 回调，处理 timer 事件
        if (rlm->_observerMask & kCFRunLoopBeforeTimers) __CFRunLoopDoObservers(rl, rlm, kCFRunLoopBeforeTimers);
        // 通知 observer， 即将触发 source0回调
        if (rlm->_observerMask & kCFRunLoopBeforeSources) __CFRunLoopDoObservers(rl, rlm, kCFRunLoopBeforeSources);

// 执行加入 RunLoop 的 block
	__CFRunLoopDoBlocks(rl, rlm);

// 处理 source0类型事件 __CFRunLoopDoSources0 函数有事件处理返回true，没有事件处理返回 false
        Boolean sourceHandledThisLoop = __CFRunLoopDoSources0(rl, rlm, stopAfterHandle);
        if (sourceHandledThisLoop) {
            // 有source0事件处理去执行加入当前 RunLoop 的 block
            __CFRunLoopDoBlocks(rl, rlm);
	}
    // 如果没有 source0事件处理， 并且没有 超时，则 poll 为 false
    // 如果有 source0事件需要处理或者超时，poll 为 true
        Boolean poll = sourceHandledThisLoop || (NULL == timeout_context->termTSR);
// 第一次 loop 不会走，因为didDispatchPortLastTime 初始化为 true
        if (MACH_PORT_NULL != dispatchPort && !didDispatchPortLastTime) {
#if DEPLOYMENT_TARGET_MACOSX || DEPLOYMENT_TARGET_EMBEDDED || DEPLOYMENT_TARGET_EMBEDDED_MINI
            msg = (mach_msg_header_t *)msg_buffer;
            //从缓冲区读取消息
            if (__CFRunLoopServiceMachPort(dispatchPort, &msg, sizeof(msg_buffer), &livePort, 0, &voucherState, NULL)) {
                // 接受dispatchPort端口的消息，去处理 msg
                goto handle_msg;
            }
#elif DEPLOYMENT_TARGET_WINDOWS
            if (__CFRunLoopWaitForMultipleObjects(NULL, &dispatchPort, 0, 0, &livePort, NULL)) {
                // 如果有事件在等待，去处理
                goto handle_msg;
            }
#endif
        }

        didDispatchPortLastTime = false;

        // 通知 observer RunLoop 即将进入休眠
	if (!poll && (rlm->_observerMask & kCFRunLoopBeforeWaiting)) __CFRunLoopDoObservers(rl, rlm, kCFRunLoopBeforeWaiting);
    //设置 RunLoop 为休眠状态
	__CFRunLoopSetSleeping(rl);
	// do not do any user callouts after this point (after notifying of sleeping)

        // Must push the local-to-this-activation ports in on every loop
        // iteration, as this mode could be run re-entrantly and we don't
        // want these ports to get serviced.

        __CFPortSetInsert(dispatchPort, waitSet);

	__CFRunLoopModeUnlock(rlm);
	__CFRunLoopUnlock(rl);

        CFAbsoluteTime sleepStart = poll ? 0.0 : CFAbsoluteTimeGetCurrent();

#if DEPLOYMENT_TARGET_MACOSX || DEPLOYMENT_TARGET_EMBEDDED || DEPLOYMENT_TARGET_EMBEDDED_MINI
#if USE_DISPATCH_SOURCE_FOR_TIMERS

// 又有一个循环， 用于接收等待端口的消息
// 进入此循环后，线程 sleep，直到收到消息才会跳出循环，继续 RunLoop
        do {
            if (kCFUseCollectableAllocator) {
                // objc_clear_stack(0);
                // <rdar://problem/16393959>
                memset(msg_buffer, 0, sizeof(msg_buffer));
            }
            msg = (mach_msg_header_t *)msg_buffer;
            // 接受 waitSet 端口的消息
            __CFRunLoopServiceMachPort(waitSet, &msg, sizeof(msg_buffer), &livePort, poll ? 0 : TIMEOUT_INFINITY, &voucherState, &voucherCopy);

            // 接收到新消息
            if (modeQueuePort != MACH_PORT_NULL && livePort == modeQueuePort) {
                // Drain the internal queue. If one of the callout blocks sets the timerFired flag, break out and service the timer.
                while (_dispatch_runloop_root_queue_perform_4CF(rlm->_queue));
                if (rlm->_timerFired) {
                    // Leave livePort as the queue port, and service timers below
                    rlm->_timerFired = false;
                    break;
                } else {
                    if (msg && msg != (mach_msg_header_t *)msg_buffer) free(msg);
                }
            } else {
                // Go ahead and leave the inner loop.
                break;
            }
        } while (1);
#else

// 跳出循环，表示有新消息到
        if (kCFUseCollectableAllocator) {
            // objc_clear_stack(0);
            // <rdar://problem/16393959>
            memset(msg_buffer, 0, sizeof(msg_buffer));
        }
        msg = (mach_msg_header_t *)msg_buffer;
        __CFRunLoopServiceMachPort(waitSet, &msg, sizeof(msg_buffer), &livePort, poll ? 0 : TIMEOUT_INFINITY, &voucherState, &voucherCopy);
#endif


#elif DEPLOYMENT_TARGET_WINDOWS
        // Here, use the app-supplied message queue mask. They will set this if they are interested in having this run loop receive windows messages.
        __CFRunLoopWaitForMultipleObjects(waitSet, NULL, poll ? 0 : TIMEOUT_INFINITY, rlm->_msgQMask, &livePort, &windowsMessageReceived);
#endif

        __CFRunLoopLock(rl);
        __CFRunLoopModeLock(rlm);

        rl->_sleepTime += (poll ? 0.0 : (CFAbsoluteTimeGetCurrent() - sleepStart));

        // Must remove the local-to-this-activation ports in on every loop
        // iteration, as this mode could be run re-entrantly and we don't
        // want these ports to get serviced. Also, we don't want them left
        // in there if this function returns.

        __CFPortSetRemove(dispatchPort, waitSet);
        // 解除RunLoop 的休眠状态
        __CFRunLoopSetIgnoreWakeUps(rl);

        // user callouts now OK again
	__CFRunLoopUnsetSleeping(rl);
	if (!poll && (rlm->_observerMask & kCFRunLoopAfterWaiting)) __CFRunLoopDoObservers(rl, rlm, kCFRunLoopAfterWaiting);

    // 处理收到的消息
        handle_msg:;
        __CFRunLoopSetIgnoreWakeUps(rl);

#if DEPLOYMENT_TARGET_WINDOWS
        if (windowsMessageReceived) {
            // These Win32 APIs cause a callout, so make sure we're unlocked first and relocked after
            __CFRunLoopModeUnlock(rlm);
	    __CFRunLoopUnlock(rl);

            if (rlm->_msgPump) {
                rlm->_msgPump();
            } else {
                MSG msg;
                if (PeekMessage(&msg, NULL, 0, 0, PM_REMOVE | PM_NOYIELD)) {
                    TranslateMessage(&msg);
                    DispatchMessage(&msg);
                }
            }

            __CFRunLoopLock(rl);
	    __CFRunLoopModeLock(rlm);
 	    sourceHandledThisLoop = true;

            // To prevent starvation of sources other than the message queue, we check again to see if any other sources need to be serviced
            // Use 0 for the mask so windows messages are ignored this time. Also use 0 for the timeout, because we're just checking to see if the things are signalled right now -- we will wait on them again later.
            // NOTE: Ignore the dispatch source (it's not in the wait set anymore) and also don't run the observers here since we are polling.
            __CFRunLoopSetSleeping(rl);
            __CFRunLoopModeUnlock(rlm);
            __CFRunLoopUnlock(rl);

            __CFRunLoopWaitForMultipleObjects(waitSet, NULL, 0, 0, &livePort, NULL);

            __CFRunLoopLock(rl);
            __CFRunLoopModeLock(rlm);
            __CFRunLoopUnsetSleeping(rl);
            // If we have a new live port then it will be handled below as normal
        }


#endif
        if (MACH_PORT_NULL == livePort) {
            CFRUNLOOP_WAKEUP_FOR_NOTHING();
            // handle nothing
        } else if (livePort == rl->_wakeUpPort) {
            CFRUNLOOP_WAKEUP_FOR_WAKEUP();
            // do nothing on Mac OS
#if DEPLOYMENT_TARGET_WINDOWS
            // Always reset the wake up port, or risk spinning forever
            ResetEvent(rl->_wakeUpPort);
#endif
        }
#if USE_DISPATCH_SOURCE_FOR_TIMERS
        else if (modeQueuePort != MACH_PORT_NULL && livePort == modeQueuePort) {
            // 定时器事件唤醒 RunLoop
            CFRUNLOOP_WAKEUP_FOR_TIMER();
            // 处理 timer 事件
            if (!__CFRunLoopDoTimers(rl, rlm, mach_absolute_time())) {
                // Re-arm the next timer, because we apparently fired early
                __CFArmNextTimerInMode(rlm, rl);
            }
        }
#endif
#if USE_MK_TIMER_TOO
        // 定时器事件
        else if (rlm->_timerPort != MACH_PORT_NULL && livePort == rlm->_timerPort) {
            CFRUNLOOP_WAKEUP_FOR_TIMER();
            // On Windows, we have observed an issue where the timer port is set before the time which we requested it to be set. For example, we set the fire time to be TSR 167646765860, but it is actually observed firing at TSR 167646764145, which is 1715 ticks early. The result is that, when __CFRunLoopDoTimers checks to see if any of the run loop timers should be firing, it appears to be 'too early' for the next timer, and no timers are handled.
            // In this case, the timer port has been automatically reset (since it was returned from MsgWaitForMultipleObjectsEx), and if we do not re-arm it, then no timers will ever be serviced again unless something adjusts the timer list (e.g. adding or removing timers). The fix for the issue is to reset the timer here if CFRunLoopDoTimers did not handle a timer itself. 9308754
            if (!__CFRunLoopDoTimers(rl, rlm, mach_absolute_time())) {
                // Re-arm the next timer
                __CFArmNextTimerInMode(rlm, rl);
            }
        }
#endif
        else if (livePort == dispatchPort) {
            CFRUNLOOP_WAKEUP_FOR_DISPATCH();
            __CFRunLoopModeUnlock(rlm);
            __CFRunLoopUnlock(rl);
            _CFSetTSD(__CFTSDKeyIsInGCDMainQ, (void *)6, NULL);
#if DEPLOYMENT_TARGET_WINDOWS
            void *msg = 0;
#endif
            __CFRUNLOOP_IS_SERVICING_THE_MAIN_DISPATCH_QUEUE__(msg);
            _CFSetTSD(__CFTSDKeyIsInGCDMainQ, (void *)0, NULL);
            __CFRunLoopLock(rl);
            __CFRunLoopModeLock(rlm);
            sourceHandledThisLoop = true;
            didDispatchPortLastTime = true;
        } else {
            CFRUNLOOP_WAKEUP_FOR_SOURCE();

            // If we received a voucher from this mach_msg, then put a copy of the new voucher into TSD. CFMachPortBoost will look in the TSD for the voucher. By using the value in the TSD we tie the CFMachPortBoost to this received mach_msg explicitly without a chance for anything in between the two pieces of code to set the voucher again.
            voucher_t previousVoucher = _CFSetTSD(__CFTSDKeyMachMessageHasVoucher, (void *)voucherCopy, os_release);

            // Despite the name, this works for windows handles as well
            CFRunLoopSourceRef rls = __CFRunLoopModeFindSourceForMachPort(rl, rlm, livePort);
            if (rls) {
#if DEPLOYMENT_TARGET_MACOSX || DEPLOYMENT_TARGET_EMBEDDED || DEPLOYMENT_TARGET_EMBEDDED_MINI
		mach_msg_header_t *reply = NULL;
        // 处理 source1类型事件
		sourceHandledThisLoop = __CFRunLoopDoSource1(rl, rlm, rls, msg, msg->msgh_size, &reply) || sourceHandledThisLoop;
		if (NULL != reply) {
		    (void)mach_msg(reply, MACH_SEND_MSG, reply->msgh_size, 0, MACH_PORT_NULL, 0, MACH_PORT_NULL);
		    CFAllocatorDeallocate(kCFAllocatorSystemDefault, reply);
		}
#elif DEPLOYMENT_TARGET_WINDOWS
                sourceHandledThisLoop = __CFRunLoopDoSource1(rl, rlm, rls) || sourceHandledThisLoop;
#endif
	    }

            // Restore the previous voucher
            _CFSetTSD(__CFTSDKeyMachMessageHasVoucher, previousVoucher, os_release);

        }
#if DEPLOYMENT_TARGET_MACOSX || DEPLOYMENT_TARGET_EMBEDDED || DEPLOYMENT_TARGET_EMBEDDED_MINI
        if (msg && msg != (mach_msg_header_t *)msg_buffer) free(msg);
#endif

	__CFRunLoopDoBlocks(rl, rlm);


	if (sourceHandledThisLoop && stopAfterHandle) {
        // 进入 RunLoop 时传入的参数处理完 source 后返回
	    retVal = kCFRunLoopRunHandledSource;
        } else if (timeout_context->termTSR < mach_absolute_time()) {
            // 超时的情况
            retVal = kCFRunLoopRunTimedOut;
	} else if (__CFRunLoopIsStopped(rl)) {
        //手动终止 RunLoop
            __CFRunLoopUnsetStopped(rl);
	    retVal = kCFRunLoopRunStopped;
	} else if (rlm->_stopped) {
        // mode 发生变化，停止
	    rlm->_stopped = false;
	    retVal = kCFRunLoopRunStopped;
	} else if (__CFRunLoopModeIsEmpty(rl, rlm, previousMode)) {
        // mode 中没有事件处理
	    retVal = kCFRunLoopRunFinished;
	}

#if DEPLOYMENT_TARGET_MACOSX || DEPLOYMENT_TARGET_EMBEDDED || DEPLOYMENT_TARGET_EMBEDDED_MINI
        voucher_mach_msg_revert(voucherState);
        os_release(voucherCopy);
#endif

    } while (0 == retVal);

    if (timeout_timer) {
        dispatch_source_cancel(timeout_timer);
        dispatch_release(timeout_timer);
    } else {
        free(timeout_context);
    }

    return retVal;
}
```
从代码中可以看出 RunLoop 是基于 mach port 实现的。从源码中也可以看到 RunLoop 对于事件的处理过程是和之前那张图一致的，前人已经帮我们总结了 RunLoop 的运行过程，阅读源码主要是验证和对 RunLoop 运行过程的理解，源码中加了部分注释，耐心地阅读几遍即可发现 RunLoop 的运行过程了。
