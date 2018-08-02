# RunLoop 的相关概念
此篇为对 RunLoop 的相关概念的总结，主要介绍 RunLoop 的一些概念

## RunLoop 简介
* RunLoop 是与线程相关联的基础架构，它可以使得线程在没有任务到来时空闲，在有任务到来时运行起来。所以，RunLoop 管理了其需要处理的任务和消息。

* RunLoop 是一个对象，提供一个入口函数，当线程执行此函数后，会进入 接受消息->等待->处理消息 的循环中。一直到这个循环结束（手动终止或其他情况)，函数返回。

* RunLoop 不是完全自主管理的，需要在适当的时候启动它。

* 不需要自己去创建 RunLoop，每个线程都有一个对应的 RunLoop 对象。

* 只有子线程的 RunLoop 需要手动启动，主线程的 RunLoop 在 APP 启动时就已经运行了。

* Cocoa和 Core Foundation 框架都提供了 RunLoop 相关的 API：NSRunLoop 和 CFRunLoopRef。
    * CFRunLoopRef 是 Core Foundation 框架内的，提供 了纯 C 语言的 API，这些 API 都是线程安全的。可以在任何线程中调用。
    * NSRunLoop 是 Cocoa 框架内的，NSRunLoop 是基于 CFRunLoopRef 的封装，提供了面向对象的 API，但是这个 API 不是线程安全的。在某个线程中只操作该线程的 RunLoop，而不要跨线程向 RunLoop 添加 source，否则可能会 crash。

## RunLoop 与线程的关系

上面说到 RunLoop 与线程是一一对应的，这种对应关系是通过全局的字典保存的。线程在刚创建时没有 RunLoop，需要主动去获取，RunLoop 是在第一次获取时才会去创建。RunLoop 的销毁是在线程结束时，对于主线程的 RunLoop，我们何时都能获取到，但是对于子线程，我们只能在该线程内部才能获取其 RunLoop 对象。

## 剖析 RunLoop
一个 RunLoop 包含若干个 mode，每个 mode 又包含若干个 source/Timer/Observer。如下图：

![RunLoop](https://github.com/taoclouds/RunLoop-Learn/blob/master/image/runloop.png?raw=true)

### 与 RunLoop 的相关类：
* CFRunLoopRef

    它代表了一个 RunLoop 对象。

* CFRunLoopSourceRef

CFRunLoopSourceRef 产生事件的来源，通常事件来源分为两种：source0和 source1。source0包含一个回调函数，它不能主动触发。使用时需要先标记 source0事件为待处理，然后手动唤醒 RunLoop，让它处理这个 source0事件。 source1则包含一个 mach 端口和一个回调函数。用于内核和线程之间发送消息。source1可以主动唤醒 RunLoop。

* CFRunLoopTimerRef

基于时间的触发器，和 NSTimer 是可以混用的，包含一个时间长度和一个回调函数。在其加入到 RunLoop 时，RunLoop 会注册对应的时间点，当时间到时，回调函数会被执行。
* CFRunLoopObserverRef

观察者，每个 observer 都包含一个回调函数，当 RunLoop 的状态发生变化时，观察者能够通过回调接收到这个变化。比如在线程运行前需要做一些处理即可通过回调实现。
可以监听的 RunLoop 状态包括：
1. 即将进入RunLoop
2. RunLoop 即将处理 timer source
3. RunLoop 即将处理 input source
4. RunLoop 即将进入休眠
5. RunLoop 被唤醒，但还没开始处理事件
6. RunLoop 退出


* CFRunLoopModeRef
CFRunLoopModeRef 是 RunLoop 的运行 mode。在 RunLoop 中，有以下几种 mode：

    * NSDefaultRunLoopMode(Cooca) kCFRunLoopDefaultMode (Core Foundation)

    都是默认的 Mode，APP 运行起来之后，主线程的 RunLoop 默认运行在该 Mode 下。
    * GSEventReceiveRunLoopMode(Cocoa)

    接受系统内部事件
    * UIInitializationRunLoopMode(Cocoa)

    APP 初始化的时候运行在该 Mode 下
    * UITrackingRunLoopMode(Cocoa)

    追踪触摸手势，确保界面刷新时不会卡顿，滑动 tableview，scrollview 等都运行在该模式下
    * NSRunLoopCommonModes(Cocoa) kCFRunLoopCommonModes (Core Foundation)

    commonModes 是特殊的模式

上面的 Source/Timer/Observer 统一称作 Mode item。一个 item 可以被同时加在多个 mode 里。重复加入 item 只会有一次运行效果。如果 mode 里面没有 item，则 RunLoop 会直接退出。

* 每次调用 RunLoop 的主函数时，只能指定其中一个 mode 作为 RunLoop 的运行模式。

* 在切换 RunLoop 的模式时，只能退出当前的 mode，再重新指定一个 mode 重新进入。

* RunLoop 在运行时只处理当前 mode 中的事件，其它 mode 中的事件会被暂停。

* 可以自定义 mode，不过为了确保 mode 生效，它至少需要一个 source 或者 timer 或者 observer。

### RunLoop 中的事件源(input source)
#### 基于内核端口的事件源
Cocoa和Core Foundation都提供了Port-Based source的支持。
#### 自定义事件源
Perform Selector 接口
* 使用**performSelector**系列API往某个线程添加事件的时候，你必须要确保目标线程的RunLoop是运行的。否则该事件不会被执行，这里要注意一下，子线程的RunLoop不是默认启动的。

定时器
* 定时器事件在时间到了就会执行。就像input source一样，timer需要被加入到指定的Mode中，并且RunLoop要运行在这个Mode下，timer才有效。
* Runloop中的定时器不是精准定时器。RunLoop是一个循环一直跑，在某次循环运行中途加入的定时器事件，只有等到下一次循环才会被执行。

### RunLoop 对于事件的处理顺序
1. 通知 observers 已经进入 RunLoop
2. 通知 observers 即将开始处理 timer source
3. 通知 observers 即将开始处理 input source（不包括内核事件）
4. 开始处理 input source（不包括内核事件）
5. 如果有内核事件，开始处理内核事件 跳到第9步
6. 通知 observers 线程即将休眠
7. 线程进入休眠，知道有如下事件发生：
    * 受到内核消息
    * 定时器事件需要执行
    * RunLoop 超时时间到
    * 手动唤醒了 RunLoop
8. 通知 observers RunLoop被唤醒
9. 处理待处理的事件：
    * 如果自定义的 timer 被 fire，则执行定时器的事件并重新 loop，跳到第2步。
    * 如果 input source 被 fire，则处理该事件。
    * 若 RunLoop 被手动唤醒，且未超时，那么重新 loop，跳到第2步。
10. 退出 RunLoop，通知 observer RunLoop 已经退出。


 RunLoop 可以被手动唤醒，在增加一个 input source 后唤醒 RunLoop 确保 input source能够立刻被执行，不用等到下一次 loop。


 ### 什么时候使用 RunLoop？
在创建一个子线程的时候，需要手动地开启 RunLoop。对于主线程，RunLoop 是自动启动的。
是否需要启动子线程的 RunLoop：
* 需要和其它线程通信时
* 需要在子线程中使用 timer
* 使用了 performSelecctor API
* 需要线程执行某个周期性任务时。
