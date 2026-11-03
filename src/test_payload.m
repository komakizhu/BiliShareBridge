/*
 * Copyright (C) 2026 Komaki Zhu
 * SPDX-License-Identifier: GPL-3.0-only
 */
#import "SharePayload.h"

@interface TestMedia : NSObject
@property NSString *webpageUrl;
@property NSString *videoUrl;
@property NSData *imageData;
@end
@implementation TestMedia
@end
@interface TestMessage : NSObject
@property id mediaObject;
@end
@implementation TestMessage
@end
@interface TestRequest : NSObject
@property TestMessage *message;
@property NSString *text;
@end
@implementation TestRequest
@end

static NSUInteger checks;
static void Check(BOOL result, NSString *message) {
    checks++;
    if (!result) { NSLog(@"FAIL: %@", message); exit(1); }
}

int main(void) { @autoreleasepool {
    Check([BLWebURL(@"https://b23.tv/AbCd").absoluteString isEqual:@"https://b23.tv/AbCd"], @"short link unchanged");
    Check([BLWebURL(@"bilibili://video/123?page=2&share_from=x").absoluteString isEqual:@"https://www.bilibili.com/video/av123?p=2"], @"numeric video and page");
    Check([BLWebURL(@"bilibili://video/BV1xx411c7mD").absoluteString isEqual:@"https://www.bilibili.com/video/BV1xx411c7mD"], @"BV video");
    Check([BLWebURL(@"bilibili://pgc/season/ep/123").absoluteString isEqual:@"https://www.bilibili.com/bangumi/play/ep123"], @"episode link");
    Check(BLWebURL(@"weixin://app/request") == nil, @"do not forward SDK callback");
    Check(BLWebURL(@"javascript:alert(1)") == nil, @"unsupported URL scheme");
    Check(BLWebURL((id)@1) == nil, @"malformed property type");
    NSURL *own = [NSURL URLWithString:@"bilitwin://video/BV123?p=2"];
    Check([BLRewriteScheme(own, @"bilitwin", @"bilibili").absoluteString isEqual:@"bilibili://video/BV123?p=2"], @"incoming private link");
    NSURL *wechat = [NSURL URLWithString:@"wxcb8d4298c6a09bcb://response?x=1"];
    Check(BLRewriteScheme(wechat, @"bilibili", @"bilitwin") == wechat, @"external callback unchanged");
    Check(BLRewriteScheme(nil, @"bilitwin", @"bilibili") == nil, @"nil URL");
    NSURL *relative = [NSURL URLWithString:@"video/123"];
    Check(BLRewriteScheme(relative, @"bilibili", @"bilitwin") == relative, @"relative URL remains untouched");
    TestRequest *request = [TestRequest new];
    request.message = [TestMessage new];
    TestMedia *media = [TestMedia new]; request.message.mediaObject = media;
    media.webpageUrl = @"https://www.bilibili.com/video/BV123";
    Check([BLShareItems(request).firstObject isKindOfClass:NSURL.class], @"mini program fallback webpage becomes a URL");
    media.webpageUrl = nil; media.videoUrl = @"bilibili://video/456";
    Check([BLShareItems(request).firstObject absoluteString] != nil, @"video media URL");
    media.videoUrl = nil; request.text = @"文字分享";
    Check([BLShareItems(request).firstObject isEqual:@"文字分享"], @"text share");
    request.text = nil; media.imageData = [@"image" dataUsingEncoding:NSUTF8StringEncoding];
    Check([BLShareItems(request).firstObject isKindOfClass:NSData.class], @"image payload passed to UIKit for decoding");
    media.imageData = nil;
    Check(BLShareItems(request).count == 0, @"empty media fails without replacing it with a title");
    Check(BLShareItems([NSObject new]).count == 0, @"unknown request is safe");
    printf("PASS: %lu payload and URL checks\n", (unsigned long)checks);
} return 0; }
