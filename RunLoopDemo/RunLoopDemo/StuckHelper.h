//
//  StuckHelper.h
//  RunLoopDemo
//
//  Created by anson on 2018/8/3.
//  Copyright © 2018年 anson. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UITableViewCell.h>
typedef BOOL(^eventBlock) (void);

@interface StuckHelper : NSObject

@property (nonatomic, assign) NSInteger maxQueueLength;

- (void)addTaskBlock:(eventBlock)event withKey:(id)key;

- (void)removeAllTasks;

+ (instancetype)shareHelper;

@end

@interface UITableViewCell (StuckHelper)

@property (nonatomic, strong) NSIndexPath *currentIndexPath;

@end
