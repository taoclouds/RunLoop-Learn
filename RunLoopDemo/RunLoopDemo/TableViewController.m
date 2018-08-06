//
//  TableViewController.m
//  RunLoopDemo
//
//  Created by anson on 2018/8/3.
//  Copyright © 2018年 anson. All rights reserved.
//

#import "TableViewController.h"
#import "StuckHelper.h"

#define SCREEN_WIDTH    [UIScreen mainScreen].bounds.size.width
#define SCREEN_HEIGHT   [UIScreen mainScreen].bounds.size.height

@interface TableViewController () <UITableViewDelegate, UITableViewDataSource>

@property (nonatomic, strong) UITableView *mainTableView;

@property (nonatomic, strong) UIButton *clearButton;

@end

@implementation TableViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.mainTableView = [[UITableView alloc] initWithFrame:CGRectMake(0, 100, SCREEN_WIDTH, SCREEN_HEIGHT - 60) style:UITableViewStylePlain];
    self.mainTableView.dataSource = self;
    self.mainTableView.rowHeight = 135.f;
    [self.mainTableView registerClass:[UITableViewCell class] forCellReuseIdentifier:NSStringFromClass([UITableViewCell class])];
    [self.view addSubview:self.mainTableView];
    
    self.clearButton = [[UIButton alloc] initWithFrame:CGRectMake(SCREEN_WIDTH - 100, 70, 80, 25)];
    [self.clearButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [self.clearButton setTitle:@"一键解决" forState:UIControlStateNormal];
    [self.clearButton setBackgroundColor:[UIColor blackColor]];
    self.clearButton.titleLabel.font = [UIFont systemFontOfSize:12];
    [self.view addSubview:self.clearButton];
    [self.clearButton addTarget:self action:@selector(clearStuck) forControlEvents:UIControlEventTouchUpInside];
    
    // Do any additional setup after loading the view.
}

- (void)clearStuck {
    
}

#pragma mark - UITableViewDataSource
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 150;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:NSStringFromClass([UITableViewCell class]) forIndexPath:indexPath];
    [cell setSelectionStyle:UITableViewCellSelectionStyleNone];
    
    //移除之前添加过的 view
    for (NSInteger i = 1; i <= 5; i++) {
        [[cell.contentView viewWithTag:i] removeFromSuperview];
    }
    
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(5, 5, 300, 25)];
    label.backgroundColor = [UIColor clearColor];
    label.textColor = [UIColor redColor];
    label.text = [NSString stringWithFormat:@"第 %ld 个label ", indexPath.row];
    label.font = [UIFont boldSystemFontOfSize:13];
    label.tag = 1;
    [cell.contentView addSubview:label];
    
    UIImageView *imageView = [[UIImageView alloc] initWithFrame:CGRectMake(105, 20, 85, 85)];
    imageView.tag = 2;
    NSString *path = [[NSBundle mainBundle] pathForResource:@"picture" ofType:@"jpg"];
    UIImage *image = [UIImage imageWithContentsOfFile:path];
    imageView.contentMode = UIViewContentModeScaleAspectFit;
    //    imageView.image = image;
    [imageView performSelectorOnMainThread:@selector(setImage:) withObject:image waitUntilDone:NO modes:@[NSDefaultRunLoopMode]];
    NSLog(@"current:%@",[NSRunLoop currentRunLoop].currentMode);
    [cell.contentView addSubview:imageView];
    
    UIImageView *imageView2 = [[UIImageView alloc] initWithFrame:CGRectMake(200, 20, 85, 85)];
    imageView2.tag = 3;
    UIImage *image2 = [UIImage imageWithContentsOfFile:path];
    imageView2.contentMode = UIViewContentModeScaleAspectFit;
    //    imageView2.image = image2;
    [imageView2 performSelectorOnMainThread:@selector(setImage:) withObject:image2 waitUntilDone:NO modes:@[NSDefaultRunLoopMode]];
    [cell.contentView addSubview:imageView2];
    
    UILabel *label2 = [[UILabel alloc] initWithFrame:CGRectMake(5, 99, 300, 35)];
    label2.lineBreakMode = NSLineBreakByWordWrapping;
    label2.numberOfLines = 0;
    label2.backgroundColor = [UIColor clearColor];
    label2.textColor = [UIColor colorWithRed:0 green:100.f/255.f blue:0 alpha:1];
    label2.text = [NSString stringWithFormat:@"第 %ld 个label .", indexPath.row];
    label2.font = [UIFont boldSystemFontOfSize:13];
    label2.tag = 4;
    
    UIImageView *imageView3 = [[UIImageView alloc] initWithFrame:CGRectMake(5, 20, 85, 85)];
    imageView3.tag = 5;
    UIImage *image3 = [UIImage imageWithContentsOfFile:path];
    imageView3.contentMode = UIViewContentModeScaleAspectFit;
    //    imageView3.image = image3;
    [imageView3 performSelectorOnMainThread:@selector(setImage:) withObject:image3 waitUntilDone:NO modes:@[NSDefaultRunLoopMode]];
    [cell.contentView addSubview:label2];
    [cell.contentView addSubview:imageView3];
    
    return cell;
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
