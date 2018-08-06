//
//  NextViewController.m
//  RunLoopDemo
//
//  Created by anson on 2018/8/3.
//  Copyright © 2018年 anson. All rights reserved.
//

#import "NextViewController.h"
#import "WThread.h"
#import "TableViewController.h"

@interface NextViewController ()

@property (nonatomic, strong) WThread *thread;

@property (nonatomic, strong) UIButton *skipButton;

@end

@implementation NextViewController

//这个 VC 主要探究 RunLoop 与线程之间的关系.
// 线程保活
/*
 * 子线程通常处理耗时操作
 **/

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.skipButton = [[UIButton alloc] initWithFrame:CGRectMake(150, 50, 80, 25)];
    [self.skipButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [self.skipButton setTitle:@"下一页" forState:UIControlStateNormal];
    [self.skipButton setBackgroundColor:[UIColor blackColor]];
    self.skipButton.titleLabel.font = [UIFont systemFontOfSize:12];
    [self.view addSubview:self.skipButton];
    [self.skipButton addTarget:self action:@selector(nextVC) forControlEvents:UIControlEventTouchUpInside];
    
//    [self threadTest];
    
    // Do any additional setup after loading the view.
}

- (void)nextVC {
    TableViewController *tableVC = [[TableViewController alloc] init];
    tableVC.view.backgroundColor = [UIColor whiteColor];
    [self presentViewController:tableVC animated:YES completion:nil];
}

- (void)threadTest {
    WThread *thread = [[WThread alloc] initWithTarget:self selector:@selector(threadFunction) object:nil];
    self.thread = thread;
    [thread setName:@"WThread"];
    [thread start];
}

- (void)threadFunction {
    @autoreleasepool {
        //开启线程后 启动 RunLoop
        NSRunLoop *loop = [NSRunLoop currentRunLoop];
        [loop addPort:[NSMachPort port] forMode:NSRunLoopCommonModes];
        NSLog(@"启动 RunLoop 前的模式：  %@", loop.currentMode);
        [loop run];
    }
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
//    [self performSelector:@selector(threadRun) onThread:self.thread withObject:nil waitUntilDone:YES];
    WThread *thread = [[WThread alloc] initWithTarget:self selector:@selector(threadRun) object:nil];
    self.thread = thread;
    [thread setName:@"WThread"];
    [thread start];
}

- (void)threadRun {
    // 启动 RunLoop 后，
//    NSLog(@"启动 RunLoop 后的模式：  %@", [NSRunLoop currentRunLoop].currentMode);
//    NSRunLoop *loop = [NSRunLoop currentRunLoop];
    NSLog(@"开始子线程 %@", [NSThread currentThread]);
    [NSThread sleepForTimeInterval:3.0];
//    NSLog(@"启动 RunLoop 前的模式：  %@", loop.currentMode);
    NSLog(@"结束子线程 %@", [NSThread currentThread]);
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

@end
