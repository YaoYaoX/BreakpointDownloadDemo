//
//  ViewController.m
//  BreakpointDownloadDemo
//
//  Created by YaoYaoX on 2017/8/3.
//  Copyright © 2017年 YY. All rights reserved.
//

#import "ViewController.h"
#import "YYDownloadManager.h"

@interface ViewController ()

@property (nonatomic, weak) IBOutlet UIProgressView *progressView;
@property (nonatomic, strong) NSURLSessionDownloadTask *downloadTask;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
}

- (NSString *)testFileUrl{
    // github desktop 的下载地址
    NSString *url = @"https://desktop.githubusercontent.com/releases/0.7.2-cb858085/GitHubDesktop.zip";
    return url;
}

- (IBAction)start:(id)sender {
    
    NSString *fileUrl = [self testFileUrl];
    NSString *dstUrl = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSLog(@"\n\n%@\n\n",dstUrl);
    dstUrl = [dstUrl stringByAppendingPathComponent:fileUrl.lastPathComponent];
    
    __weak typeof(self) weakSelf = self;
    self.downloadTask = [YYDownloadManager downloadTaskWithUrl:fileUrl destinationUrl:dstUrl progress:^(NSProgress *progress) {
        NSLog(@"%lld %lld %f",progress.totalUnitCount, progress.completedUnitCount, progress.fractionCompleted);
        dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.progressView.progress = progress.fractionCompleted;
        });
    } complete:^(NSURLResponse *response, NSURL *filePath, NSError *error) {
        NSLog(@"%@",filePath);
    }];
    [self.downloadTask resume];
}

- (IBAction)suspend:(id)sender {
    [self.downloadTask suspend];

}

- (IBAction)stop:(id)sender {
    [YYDownloadManager cancleDownloadTask:self.downloadTask];
}

@end
