//
//  StuckHelper.m
//  RunLoopDemo
//
//  Created by anson on 2018/8/3.
//  Copyright © 2018年 anson. All rights reserved.
//

#import "StuckHelper.h"
#import <objc/runtime.h>

@interface StuckHelper ()

// 任务队列
@property (nonatomic, strong) NSMutableArray *tasks;

@property (nonatomic, strong) NSMutableArray *tasksKeys;

@property (nonatomic, strong) NSTimer *timer;

@end

@implementation StuckHelper

- (instancetype)init {
    if (self = [super init]) {
        _maxQueueLength = 30;
        _tasks = [NSMutableArray array];
        _tasksKeys = [NSMutableArray array];
        _timer = [NSTimer scheduledTimerWithTimeInterval:0.1 target:self selector:@selector(timeFiredMethod) userInfo:nil repeats:YES];
    }
    return self;
}

- (void)addTaskBlock:(eventBlock)event withKey:(id)key {
    [self.tasks addObject:event];
    [self.tasksKeys addObject:key];
    if (self.tasks.count > self.maxQueueLength) {
        [self.tasks removeObjectAtIndex:0];
        [self.tasksKeys removeObjectAtIndex:0];
    }
}

- (void)removeAllTasks {
    [self.tasks removeAllObjects];
    [self.tasksKeys removeAllObjects];
}

// 注册监听者侦查 RunLoop
+ (void)registerObserversWithHelper:(StuckHelper *)helper {
    static CFRunLoopObserverRef observer;
    CFRunLoopObserverCallBack callBack = &callBackFunction;
    
    CFRunLoopRef runloop = CFRunLoopGetCurrent();
    CFRunLoopObserverContext context = {
        0,
        (__bridge void *)helper,
        &CFRetain,
        &CFRelease,
        NULL
    };
    observer = CFRunLoopObserverCreate(NULL, kCFRunLoopBeforeWaiting, YES, NSIntegerMax - 999, callBack, &context);
    CFRunLoopAddObserver(runloop, observer, kCFRunLoopDefaultMode);
    CFRelease(observer);
}

+ (instancetype)shareHelper {
    static dispatch_once_t onceToken;
    static StuckHelper *instance = nil;
    dispatch_once(&onceToken, ^{
        instance = [[StuckHelper alloc] init];
        [self registerObserversWithHelper:instance];
    });
    return instance;
}

- (void)timeFiredMethod {
    
}

static void callBackFunction(CFRunLoopObserverRef observer, CFRunLoopActivity activity, void *info) {
    StuckHelper *helper = (__bridge StuckHelper *)info;
    if (helper.tasks.count == 0) {
        return;
    }
    BOOL result = NO;
    while (!result && helper.tasks.count) {
        eventBlock unit  = helper.tasks.firstObject;
        result = unit();
        [helper.tasks removeObjectAtIndex:0];
        [helper.tasksKeys removeObjectAtIndex:0];
    }
}

@end

@implementation UITableViewCell (StuckHelper)

@dynamic currentIndexPath;

- (NSIndexPath *)currentIndexPath {
    NSIndexPath *indexPath = objc_getAssociatedObject(self, @selector(currentIndexPath));
    return indexPath;
}

- (void)setCurrentIndexPath:(NSIndexPath *)currentIndexPath {
    objc_setAssociatedObject(self, @selector(currentIndexPath), currentIndexPath, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@end
