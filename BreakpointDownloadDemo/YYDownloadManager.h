//
//  YYDownloadManager.h
//  BreakpointDownloadDemo
//
//  Created by YaoYaoX on 2017/8/3.
//  Copyright © 2017年 YY. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef void(^MISDownloadManagerCompletion)(NSURLResponse *response, NSURL *filePath, NSError *error);

@interface YYDownloadManager : NSObject

+ (NSURLSessionDownloadTask *)downloadTaskWithUrl:(NSString *)url
                                   destinationUrl:(NSString *)desUrl
                                         progress:(void (^)(NSProgress *))progressHandler
                                         complete:(MISDownloadManagerCompletion)completionHandler;

+ (void)suspendDownloadTask:(NSURLSessionDownloadTask *)task;

+ (void)cancleDownloadTask:(NSURLSessionDownloadTask *)task;

@end
