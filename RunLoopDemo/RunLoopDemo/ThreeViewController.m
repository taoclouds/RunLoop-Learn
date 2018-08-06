//
//  ViewController.m
//  RunLoopWorkDistribution
//
//  Created by Di Wu on 9/19/15.
//  Copyright © 2015 Di Wu. All rights reserved.
//

#import "ThreeViewController.h"
#import "StuckHelper.h"

#define kSCREEN_WIDTH       [UIScreen mainScreen].bounds.size.width
#define kSCREEN_HEIGHT      [UIScreen mainScreen].bounds.size.height

static NSString *IDENTIFIER = @"CELLIDENTIFIER";

static CGFloat CELL_HEIGHT = 135.f;

@interface ThreeViewController () <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, strong) UITableView *MainTableView;

@end

@implementation ThreeViewController

+ (void)clearSubViewTask:(UITableViewCell *)cell indexPath:(NSIndexPath *)indexPath {
    for (NSInteger i = 1; i <= 5; i++) {
        [[cell.contentView viewWithTag:i] removeFromSuperview];
    }
}

+ (void)commonTask:(UITableViewCell *)cell indexPath:(NSIndexPath *)indexPath {
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(5, 5, 300, 25)];
    label.backgroundColor = [UIColor clearColor];
    label.textColor = [UIColor redColor];
    label.text = [NSString stringWithFormat:@"Title：%ld - 顶部标题", indexPath.row];
    label.font = [UIFont boldSystemFontOfSize:13];
    label.tag = 1;
    [cell.contentView addSubview:label];
    
    UILabel *label1 = [[UILabel alloc] initWithFrame:CGRectMake(5, 99, 300, 35)];
    label1.lineBreakMode = NSLineBreakByWordWrapping;
    label1.numberOfLines = 0;
    label1.backgroundColor = [UIColor clearColor];
    label1.textColor = [UIColor colorWithRed:0 green:100.f/255.f blue:0 alpha:1];
    label1.text = [NSString stringWithFormat:@" Description %zd - 底部描述", indexPath.row];
    label1.font = [UIFont boldSystemFontOfSize:13];
    label1.tag = 4;
    [cell.contentView addSubview:label1];
}

- (void)timeTask1:(UITableViewCell *)cell indexPath:(NSIndexPath *)indexPath  {
    UIImageView *imageView = [[UIImageView alloc] initWithFrame:CGRectMake(105, 20, 85, 85)];
    imageView.tag = 2;
    NSString *path = [[NSBundle mainBundle] pathForResource:@"picture" ofType:@"jpg"];
    UIImage *image = [UIImage imageWithContentsOfFile:path];
    imageView.contentMode = UIViewContentModeScaleAspectFit;
    imageView.image = image;
    [UIView transitionWithView:cell.contentView duration:0.3 options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionTransitionCrossDissolve animations:^{
        [cell.contentView addSubview:imageView];
    } completion:^(BOOL finished) {
    }];
}

- (void)timeTask2:(UITableViewCell *)cell indexPath:(NSIndexPath *)indexPath  {
    UIImageView *imageView = [[UIImageView alloc] initWithFrame:CGRectMake(200, 20, 85, 85)];
    imageView.tag = 3;
    NSString *path = [[NSBundle mainBundle] pathForResource:@"picture" ofType:@"jpg"];
    UIImage *image = [UIImage imageWithContentsOfFile:path];
    imageView.contentMode = UIViewContentModeScaleAspectFit;
    imageView.image = image;
    [UIView transitionWithView:cell.contentView duration:0.3 options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionTransitionCrossDissolve animations:^{
        [cell.contentView addSubview:imageView];
    } completion:^(BOOL finished) {
    }];
}

- (void)timeTask3:(UITableViewCell *)cell indexPath:(NSIndexPath *)indexPath  {
    UIImageView *imageView = [[UIImageView alloc] initWithFrame:CGRectMake(5, 20, 85, 85)];
    imageView.tag = 5;
    NSString *path = [[NSBundle mainBundle] pathForResource:@"picture" ofType:@"jpg"];
    UIImage *image = [UIImage imageWithContentsOfFile:path];
    imageView.contentMode = UIViewContentModeScaleAspectFit;
    imageView.image = image;
    [UIView transitionWithView:cell.contentView duration:0.3 options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionTransitionCrossDissolve animations:^{
        [cell.contentView addSubview:imageView];
    } completion:^(BOOL finished) {
    }];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 399;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:IDENTIFIER];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.currentIndexPath = indexPath;
    [ThreeViewController clearSubViewTask:cell indexPath:indexPath];
    [ThreeViewController commonTask:cell indexPath:indexPath];
    //耗时的操作用 RunLoop 处理
    [[StuckHelper shareHelper] addTaskBlock:^BOOL{
        if (![cell.currentIndexPath isEqual:indexPath]) {
            return NO;
        }
        [self timeTask1:cell indexPath:indexPath];
        return YES;
    } withKey:indexPath];
    
    [[StuckHelper shareHelper] addTaskBlock:^BOOL{
        if (![cell.currentIndexPath isEqual:indexPath]) {
            return NO;
        }
        [self timeTask2:cell indexPath:indexPath];
        return YES;
    } withKey:indexPath];
    
    [[StuckHelper shareHelper] addTaskBlock:^BOOL{
        if (![cell.currentIndexPath isEqual:indexPath]) {
            return NO;
        }
        [self timeTask3:cell indexPath:indexPath];
        return YES;
    } withKey:indexPath];
    
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return CELL_HEIGHT;
}


- (void)loadView {
    self.view = [UIView new];
    self.MainTableView = [[UITableView alloc] initWithFrame:CGRectMake(0, 44, kSCREEN_WIDTH, kSCREEN_HEIGHT - 44) style:UITableViewStylePlain];
    self.MainTableView.delegate = self;
    self.MainTableView.dataSource = self;
    [self.view addSubview:self.MainTableView];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    [self.MainTableView registerClass:[UITableViewCell class] forCellReuseIdentifier:IDENTIFIER];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
