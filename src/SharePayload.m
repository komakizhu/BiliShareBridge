/*
 * Copyright (C) 2026 Komaki Zhu
 * SPDX-License-Identifier: GPL-3.0-only
 */
#import "SharePayload.h"
#import <objc/message.h>

id BLObjectProperty(id object, NSString *name) {
    SEL selector = NSSelectorFromString(name);
    if (!object || ![object respondsToSelector:selector]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(object, selector);
}

NSURL *BLRewriteScheme(NSURL *url, NSString *from, NSString *to) {
    if (!url || !url.scheme.length || !from.length || !to.length ||
        [url.scheme caseInsensitiveCompare:from] != NSOrderedSame) return url;
    NSURLComponents *parts = [NSURLComponents componentsWithURL:url
                                      resolvingAgainstBaseURL:NO];
    parts.scheme = to;
    return parts.URL ?: url;
}

NSURL *BLWebURL(NSString *value) {
    if (![value isKindOfClass:NSString.class] || !value.length) return nil;
    value = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSURLComponents *parts = [NSURLComponents componentsWithString:value];
    NSString *scheme = parts.scheme.lowercaseString;
    if (([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"]) && parts.host.length)
        return parts.URL;
    if (![@[@"bilibili", @"bilitwin"] containsObject:scheme]) return nil;

    NSString *host = parts.host.lowercaseString;
    NSString *path = parts.path ?: @"";
    NSString *last = path.lastPathComponent;
    NSString *web = nil;
    NSCharacterSet *digits = NSCharacterSet.decimalDigitCharacterSet;
    BOOL numeric = last.length && [last rangeOfCharacterFromSet:digits.invertedSet].location == NSNotFound;
    if ([@[@"video", @"av", @"story"] containsObject:host] && last.length) {
        if ([last hasPrefix:@"BV"] || [last hasPrefix:@"av"])
            web = [@"https://www.bilibili.com/video/" stringByAppendingString:last];
        else if (numeric)
            web = [@"https://www.bilibili.com/video/av" stringByAppendingString:last];
    } else if ([@[@"bangumi", @"pgc"] containsObject:host] && numeric) {
        NSString *kind = [path containsString:@"/ep/"] ? @"ep" : @"ss";
        web = [NSString stringWithFormat:@"https://www.bilibili.com/bangumi/play/%@%@", kind, last];
    } else if ([host isEqualToString:@"live"] && numeric) {
        web = [@"https://live.bilibili.com/" stringByAppendingString:last];
    } else if ([host isEqualToString:@"space"] && numeric) {
        web = [@"https://space.bilibili.com/" stringByAppendingString:last];
    }
    if (!web) return nil;
    NSURLComponents *result = [NSURLComponents componentsWithString:web];
    // Retain the video page number; application-only flags stay inside the app.
    for (NSURLQueryItem *query in parts.queryItems) {
        if ([@[@"p", @"page"] containsObject:query.name] && query.value.length) {
            result.queryItems = @[[NSURLQueryItem queryItemWithName:@"p" value:query.value]];
            break;
        }
    }
    return result.URL;
}

NSArray *BLShareItems(id request) {
    id message = BLObjectProperty(request, @"message");
    id media = BLObjectProperty(message, @"mediaObject");
    for (NSString *key in @[@"webpageUrl", @"videoUrl", @"musicUrl", @"musicLowBandUrl"]) {
        NSURL *url = BLWebURL(BLObjectProperty(media, key));
        if (url) return @[url];
    }
    NSString *text = BLObjectProperty(request, @"text");
    if ([text isKindOfClass:NSString.class] && text.length) return @[text];
    NSData *image = BLObjectProperty(media, @"imageData");
    if ([image isKindOfClass:NSData.class] && image.length) return @[image];
    // Do not substitute a title for an unsupported media object: that would
    // report a successful share while silently dropping the actual video.
    return @[];
}
