//
//  YYDownloadManager.m
//  BreakpointDownloadDemo
//
//  Created by YaoYaoX on 2017/8/3.
//  Copyright © 2017年 YY. All rights reserved.
//

#import "YYDownloadManager.h"
#import "AFURLSessionManager.h"
#import <objc/runtime.h>

@implementation YYDownloadManager

// 1. 生成下载任务
+ (NSURLSessionDownloadTask *)downloadTaskWithUrl:(NSString *)url
                                   destinationUrl:(NSString *)desUrl
                                         progress:(void (^)(NSProgress *))progressHandler
                                         complete:(MISDownloadManagerCompletion)completionHandler {
    
    if (!url || url.length < 1 || !desUrl || desUrl.length < 1) {
        NSError *error = [NSError errorWithDomain:@"参数不全" code:-1000 userInfo:nil];
        completionHandler(nil,nil,error);
        return nil;
    }
    
    // 参数
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:url]];
    // 目标path
    NSURL *(^destination)(NSURL *, NSURLResponse *) =
    ^NSURL * _Nonnull(NSURL * _Nonnull targetPath, NSURLResponse * _Nonnull response) {
        return [NSURL fileURLWithPath:desUrl];
    };
    // 1.3 下载完成处理
    MISDownloadManagerCompletion completeBlock =
    ^(NSURLResponse *response, NSURL *filePath, NSError *error) {
        NSLog(@"%@",error);
        // 任务完成或暂停下载
        if (!error || error.code == -999) {
            // 调用cancle的时候，任务也会结束，并返回-999错误，此时由于系统已返回resumeData，不另行处理了
            if (!error) {
                // 任务完成
                [self removeResumeInfoWithUrl:response.URL.absoluteString];
                [self removeTempFileInfoWithUrl:response.URL.absoluteString];
            }
            
            if (completionHandler) {
                completionHandler(response,filePath,error);
            }
        } else  {
            // 部分网络出错，会返回resumeData
            NSData *resumeData = error.userInfo[NSURLSessionDownloadTaskResumeData];
            [self saveResumeData:resumeData withUrl:response.URL.absoluteString];
            
            if (completionHandler) {
                completionHandler(response,filePath,error);
            }
        }
    };
    
    
    // 1. 生成任务
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
    AFURLSessionManager *manager = [[AFURLSessionManager alloc] initWithSessionConfiguration:configuration];
    NSData *resumeData = [self getResumeDataWithUrl:url];
    NSURLSessionDownloadTask *downloadTask = nil;
    if (resumeData) {
        // 1.1 有断点信息，走断点下载
        downloadTask =
        [manager downloadTaskWithResumeData:resumeData
                                   progress:progressHandler
                                destination:destination
                                completionHandler:completeBlock];
        // 删除历史恢复信息，重新下载后该信息内容已不正确，不使用，
        [self removeResumeInfoWithUrl:url];
    } else {
        // 1.2 普通下载
        downloadTask =
        [manager downloadTaskWithRequest:request
                                progress:progressHandler
                             destination:destination
                       completionHandler:completeBlock];
        
        // 1.3 保存临时文件名
        NSString *tempFileName = [self getTempFileNameWithDownloadTask:downloadTask];
        [self saveTempFileName:tempFileName withUrl:url];
    }
    return downloadTask;
}

// 开始
+ (void)startDownloadTask:(NSURLSessionDownloadTask *)task {
    [task resume];
}

// 暂停
+ (void)suspendDownloadTask:(NSURLSessionDownloadTask *)task {
    [task suspend];
}

// 取消
+ (void)cancleDownloadTask:(NSURLSessionDownloadTask *)task {
    __weak typeof(task) weakTask = task;
    [task cancelByProducingResumeData:^(NSData * _Nullable resumeData) {
        [YYDownloadManager saveResumeData:resumeData withUrl:weakTask.currentRequest.URL.absoluteString];
    }];
}

#pragma mark - tempFile

/// 获取临时文件名
+ (NSString *)getTempFileNameWithDownloadTask:(NSURLSessionDownloadTask *)downloadTask {
    //NSURLSessionDownloadTask --> 属性downloadFile：__NSCFLocalDownloadFile --> 属性path
    NSString *tempFileName = nil;
    
    // downloadTask的属性(NSURLSessionDownloadTask) dt
    unsigned int dtpCount;
    objc_property_t *dtps = class_copyPropertyList([downloadTask class], &dtpCount);
    for (int i = 0; i<dtpCount; i++) {
        objc_property_t dtp = dtps[i];
        const char *dtpc = property_getName(dtp);
        NSString *dtpName = [NSString stringWithUTF8String:dtpc];
        
        // downloadFile的属性(__NSCFLocalDownloadFile) df
        if ([dtpName isEqualToString:@"downloadFile"]) {
            id downloadFile = [downloadTask valueForKey:dtpName];
            unsigned int dfpCount;
            objc_property_t *dfps = class_copyPropertyList([downloadFile class], &dfpCount);
            for (int i = 0; i<dfpCount; i++) {
                objc_property_t dfp = dfps[i];
                const char *dfpc = property_getName(dfp);
                NSString *dfpName = [NSString stringWithUTF8String:dfpc];
                // 下载文件的临时地址
                if ([dfpName isEqualToString:@"path"]) {
                    id pathValue = [downloadFile valueForKey:dfpName];
                    NSString *tempPath = [NSString stringWithFormat:@"%@",pathValue];
                    tempFileName = tempPath.lastPathComponent;
                    break;
                }
            }
            free(dfps);
            break;
        }
    }
    free(dtps);
    
    return tempFileName;
}

/// 保存临时文件名
+ (void)saveTempFileName:(NSString *)name withUrl:(NSString *)url {
    if (url.length < 1 || name.length < 1) {
        return;
    }
    
    NSString *mapPath = [self tempFileMapPath];
    NSMutableDictionary *tempFileMap = [NSMutableDictionary dictionaryWithContentsOfFile:mapPath];
    if([tempFileMap[url] length] > 0){
        [[NSFileManager defaultManager] removeItemAtPath:[self tempFilePathWithName:tempFileMap[url]] error:nil];
    }
    if (!tempFileMap) {
        tempFileMap = [NSMutableDictionary dictionary];
    }
    tempFileMap[url] = name;
    [tempFileMap writeToFile:mapPath atomically:YES];
}

/// 移除临时文件相关信息
+ (void)removeTempFileInfoWithUrl:(NSString *)url {
    if (url.length < 1) {
        return;
    }
    
    NSString *mapPath = [self tempFileMapPath];
    NSMutableDictionary *tempFileMap = [NSMutableDictionary dictionaryWithContentsOfFile:mapPath];
    if([tempFileMap[url] length] > 0){
        [[NSFileManager defaultManager] removeItemAtPath:[self tempFilePathWithName:tempFileMap[url]] error:nil];
        [tempFileMap removeObjectForKey:url];
        [tempFileMap writeToFile:mapPath atomically:YES];
    }
}

/// 手动创建resume信息
+ (NSData *)createResumeDataWithUrl:(NSString *)url {
    if (url.length < 1) {
        return nil;
    }
    
    // 1. 从map文件中获取resumeData的name
    NSMutableDictionary *resumeMap = [NSMutableDictionary dictionaryWithContentsOfFile:[self resumeDataMapPath]];
    NSString *resumeDataName = resumeMap[url];
    if (resumeDataName.length < 1) {
        resumeDataName = [self getRandomResumeDataName];
        resumeMap[url] = resumeDataName;
        [resumeMap writeToFile:[self resumeDataMapPath] atomically:YES];
    }
    
    // 2. 获取data
    NSString *resumeDataPath = [self resumeDataPathWithName:resumeDataName];
    NSDictionary *tempFileMap = [NSDictionary dictionaryWithContentsOfFile:[self tempFileMapPath]];
    NSString *tempFileName = tempFileMap[url];
    if (tempFileName.length > 0) {
        NSString *tempFilePath = [self tempFilePathWithName:tempFileName];
        NSFileManager *fileMgr = [NSFileManager defaultManager];
        if ([fileMgr fileExistsAtPath:tempFilePath]) {
            // 获取文件大小
            NSDictionary *tempFileAttr = [[NSFileManager defaultManager] attributesOfItemAtPath:tempFilePath error:nil ];
            unsigned long long fileSize = [tempFileAttr[NSFileSize] unsignedLongLongValue];
            
            // 手动建一个resumeData
            NSMutableDictionary *fakeResumeData = [NSMutableDictionary dictionary];
            fakeResumeData[@"NSURLSessionDownloadURL"] = url;
            // ios8、与>ios9方式稍有不同
            if (NSFoundationVersionNumber >= NSFoundationVersionNumber_iOS_9_0) {
                fakeResumeData[@"NSURLSessionResumeInfoTempFileName"] = tempFileName;
            } else {
                fakeResumeData[@"NSURLSessionResumeInfoLocalPath"] = tempFilePath;
            }
            fakeResumeData[@"NSURLSessionResumeBytesReceived"] = @(fileSize);
            [fakeResumeData writeToFile:resumeDataPath atomically:YES];
            
            // 重新加载信息
            return [NSData dataWithContentsOfFile:resumeDataPath];
        }
    }
    return nil;
}

#pragma mark - resumeData
                          
+ (NSString *)getRandomResumeDataName{
    return [NSString stringWithFormat:@"ResumeData_%@.dat",[NSUUID UUID].UUIDString];
}

+ (NSString *)saveResumeData:(NSData *)resumeData withUrl:(NSString *)url{
    if (resumeData.length < 1 || url.length < 1) {
        return nil;
    }
    
    // 1. 用一个map文件记录resumeData的位置
    NSString *resumeDataName = [self getRandomResumeDataName];
    NSMutableDictionary *map = [NSMutableDictionary dictionaryWithContentsOfFile:[self resumeDataMapPath]];
    if (!map) {
        map = [NSMutableDictionary dictionary];
    }
    // 删除旧的resumeData
    if (map[url]) {
        [[NSFileManager defaultManager] removeItemAtPath:[self resumeDataPathWithName:map[url]] error:nil];
    }
    // 更新resumeInfo
    map[url] = resumeDataName;
    [map writeToFile:[self resumeDataMapPath] atomically:YES];
    
    // 2. 存储resumeData
    NSString *resumeDataPath = [self resumeDataPathWithName:resumeDataName];
    [resumeData writeToFile:resumeDataPath atomically:YES];
    
    return resumeDataName;
}

/// 获取恢复文件，文件不存在尝试手动建一个
+ (NSData *)getResumeDataWithUrl:(NSString *)url {
    if (url.length < 1) {
        return nil;
    }
    
    // 1. 从map文件中获取resumeData的name
    NSMutableDictionary *resumeMap = [NSMutableDictionary dictionaryWithContentsOfFile:[self resumeDataMapPath]];
    NSString *resumeDataName = resumeMap[url];
    
    // 2. 获取data
    NSData *resumeData = nil;
    NSString *resumeDataPath = [self resumeDataPathWithName:resumeDataName];
    if (resumeDataName.length > 0) {
        resumeData = [NSData dataWithContentsOfFile:resumeDataPath];
    }
    
    // 3. 如果没有data，找到临时文件，尝试自己建一个
    if (!resumeData) {
        resumeData = [self createResumeDataWithUrl:url];
    }
    
    return resumeData;
}

/// 删除恢复文件信息
+ (void)removeResumeInfoWithUrl:(NSString *)url {
    
    // 1. 从map文件中获取resumeData的name
    NSMutableDictionary *map = [NSMutableDictionary dictionaryWithContentsOfFile:[self resumeDataMapPath]];
    NSString *resumeDataName = map[url];
    
    if (resumeDataName) {
        // 2. 删除记录
        [map removeObjectForKey:url];
        [map writeToFile:[self resumeDataMapPath] atomically:YES];
        
        // 3. 删除resumeData
        NSString *resumeDataPath = [self resumeDataPathWithName:resumeDataName];
        [[NSFileManager defaultManager] removeItemAtPath:resumeDataPath error:nil];
    }
}

#pragma mark - 路径

/// 记录resumeData位置的map文件
+ (NSString *)resumeDataMapPath {
    // key: url  value: resumeDataName
    return [[self downloadTempFilePath] stringByAppendingPathComponent:@"ResumeDataMap.plist"];
}

/// resumeData的路径
+ (NSString *)resumeDataPathWithName:(NSString *)fileName {
    return [[self downloadTempFilePath] stringByAppendingPathComponent:fileName];
}

/// 记录tempFile位置的map文件
+ (NSString *)tempFileMapPath {
    // key: url  value: tempFileName
    return [[self downloadTempFilePath] stringByAppendingPathComponent:@"TempFileMap.plist"];
}

/// 临时文件路径
+ (NSString *)tempFilePathWithName:(NSString *)fileName {
    return [NSTemporaryDirectory() stringByAppendingPathComponent:fileName];
}

/// 记录下载信息的文件夹
+ (NSString *)downloadTempFilePath {
    NSString *path = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
    path = [path stringByAppendingPathComponent:@"DownloadTempFile"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
    }
    return path;
}

@end
