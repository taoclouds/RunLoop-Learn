# RunLoop 源码分析
此篇主要分析 RunLoop 的源码，对源码的注释在仓库中。
分析源码我主要采用的是：RunLoop 相关的结构 -> RunLoop 如何创建 -> RunLoop 如何运行 这样的路径来分析的。
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
