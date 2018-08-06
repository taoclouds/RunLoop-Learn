//
//  ViewController.m
//  RunLoopDemo
//
//  Created by anson on 2018/8/3.
//  Copyright © 2018年 anson. All rights reserved.
//

#import "ViewController.h"
#import "NextViewController.h"

static NSInteger t = 0;

@interface ViewController ()

@property (nonatomic, strong) UIImageView *imageView;

@property (nonatomic, strong) UITextView *textView;

@property (nonatomic, strong) UIButton *timerButton;

@end

@implementation ViewController

// RunLoopDemo 01 在屏幕上有个 imageView，点击屏幕后加载图片
// RunLoopDemo 02 使用 NSTimer 来改变 button 的显示

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    self.imageView = [[UIImageView alloc] initWithFrame:CGRectMake(100, 200, 100, 100)];
    self.imageView.backgroundColor = [UIColor cyanColor];
    [self.view addSubview:self.imageView];
    
    self.textView = [[UITextView alloc] initWithFrame:CGRectMake(80, 350, 100, 60)];
    self.textView.text = @"大萨达撒多是的撒多所多大大四季度会死啊大傻逼多久爱时代是的的撒的奇偶洒基";
    self.textView.backgroundColor = [UIColor lightGrayColor];
    self.textView.scrollEnabled = YES;
    self.textView.editable = YES;
    [self.view addSubview:self.textView];
    
    self.timerButton = [[UIButton alloc] initWithFrame:CGRectMake(150, 50, 80, 25)];
    [self.timerButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [self.timerButton setBackgroundColor:[UIColor orangeColor]];
    self.timerButton.titleLabel.font = [UIFont systemFontOfSize:12];
    [self.view addSubview:self.timerButton];
    [self.timerButton addTarget:self action:@selector(nextVC) forControlEvents:UIControlEventTouchUpInside];
    
    NSTimer *timer = [NSTimer timerWithTimeInterval:1.0 target:self selector:@selector(timerAction) userInfo:nil repeats:YES];
    [[NSRunLoop currentRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
    
}

- (void)timerAction {
    [self.timerButton setTitle:[NSString stringWithFormat:@"%ld", t] forState:UIControlStateNormal];
    t++;
}

- (void)nextVC {
    NextViewController *nextVC = [[NextViewController alloc] init];
    nextVC.view.backgroundColor = [UIColor whiteColor];
    [self presentViewController:nextVC animated:YES completion:nil];
}

- (void)setImage:(UIImage *) image {
    self.imageView.image = image;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self.imageView performSelector:@selector(setImage:) withObject:[UIImage imageNamed:@"backImage"] afterDelay:2.5 inModes:@[NSDefaultRunLoopMode]];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


@end
