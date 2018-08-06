//
//  StuckHelper.m
//  RunLoopDemo
//
//  Created by anson on 2018/8/3.
//  Copyright © 2018年 anson. All rights reserved.
//

#import "StuckHelper.h"

@interface StuckHelper ()

// 监控线程
@property (nonatomic, strong) NSThread *helpThread;

// 观察者
@property (assign, nonatomic) CFRunLoopObserverRef observer;

//定时器
@property (assign, nonatomic) CFRunLoopTimerRef timer;

// 判断是否在执行
@property (assign, nonatomic) BOOL idExcute;

// 开始执行的时间
@property (nonatomic, strong) NSDate *startTimer;

@property (nonatomic, assign) NSTimeInterval interval;
@property (nonatomic, assign) NSTimeInterval tol;

@end

@implementation StuckHelper

+ (instancetype)shareHelper {
    static dispatch_once_t onceToken;
    static StuckHelper *instance = nil;
    dispatch_once(&onceToken, ^{
        instance = [[StuckHelper alloc] init];
        instance.helpThread = [[NSThread alloc] init];
        [instance.helpThread start];
    });
    return instance;
}

@end
