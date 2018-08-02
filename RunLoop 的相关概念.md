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
* 一个 RunLoop 包含若干个 mode，每个 mode 又包含若干个 source/Timer/Observer。

* 每次调用 RunLoop 的主函数时，只能指定其中一个 mode 作为 RunLoop 的运行模式。
