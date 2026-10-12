// SPDX-License-Identifier: GPL-3.0-only
// OpenMuse host bridge for the pinned OpenMinis iSH ARM64 source dependency.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^OpenMuseISHCompletion)(NSData *output,
                                     int32_t exitCode,
                                     BOOL timedOut,
                                     BOOL outputTruncated,
                                     NSError * _Nullable error);
typedef void (^OpenMuseISHProgress)(NSData *output);
/// Synchronously executes one validated browser action in the active
/// conversation's shared WKWebView tab pool and returns a JSON result.
typedef NSString * _Nullable (^OpenMuseISHBrowserActionHandler)(NSString *actionJSON);

@interface OpenMuseISHBridge : NSObject

- (void)cancelCurrentExecution;
- (void)prepareForExecution;

- (void)executeCommand:(NSString *)command
           rootfsPath:(NSString *)rootfsPath
                mounts:(NSArray<NSDictionary<NSString *, id> *> *)mounts
               timeout:(NSTimeInterval)timeout
     maximumOutputBytes:(NSUInteger)maximumOutputBytes
 browserActionHandler:(nullable OpenMuseISHBrowserActionHandler)browserActionHandler
              progress:(OpenMuseISHProgress)progress
            completion:(OpenMuseISHCompletion)completion;

@end

NS_ASSUME_NONNULL_END
