/*
 * Copyright (C) 2026 Komaki Zhu
 * SPDX-License-Identifier: GPL-3.0-only
 */
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "SharePayload.h"

static void (*OriginalSendRequest)(id, SEL, id, void (^)(BOOL));
static BOOL ShareInProgress;
static NSString *PrivateScheme;

static void LogEvent(NSString *event) {
    // Log events only, without URLs, account data, titles, or SDK tokens.
    NSLog(@"[BiliShareBridge 1.1.1] %@", event);
}

static BOOL ReplaceMethod(Class cls, SEL selector, IMP replacement, IMP *original) {
    if (!cls) return NO;
    Method method = class_getInstanceMethod(cls, selector);
    if (!method) return NO;
    *original = method_getImplementation(method);
    if (!class_addMethod(cls, selector, replacement, method_getTypeEncoding(method)))
        method_setImplementation(class_getInstanceMethod(cls, selector), replacement);
    return YES;
}

static UIViewController *VisibleController(void) {
    UIWindow *window = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (scene.activationState != UISceneActivationStateForegroundActive ||
            ![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *candidate in ((UIWindowScene *)scene).windows) {
            if (candidate.isKeyWindow) { window = candidate; break; }
        }
        if (window) break;
    }
    if (!window) {
        for (UIWindow *candidate in UIApplication.sharedApplication.windows) {
            if (candidate.isKeyWindow) { window = candidate; break; }
        }
    }
    UIViewController *controller = window.rootViewController;
    for (NSUInteger i = 0; i < 24 && controller; i++) {
        if (controller.presentedViewController && !controller.presentedViewController.isBeingDismissed)
            controller = controller.presentedViewController;
        else if ([controller isKindOfClass:UINavigationController.class])
            controller = ((UINavigationController *)controller).visibleViewController;
        else if ([controller isKindOfClass:UITabBarController.class])
            controller = ((UITabBarController *)controller).selectedViewController;
        else return controller;
    }
    return nil;
}

static void NotifyShareResult(BOOL completed, NSError *error) {
    Class providerClass = NSClassFromString(@"BFCShare3rdPartyWeChat");
    SEL shared = NSSelectorFromString(@"shared");
    id provider = [providerClass respondsToSelector:shared]
        ? ((id (*)(id, SEL))objc_msgSend)(providerClass, shared) : nil;
    id response = [[NSClassFromString(@"SendMessageToWXResp") alloc] init];
    SEL setError = NSSelectorFromString(@"setErrCode:");
    SEL onResponse = NSSelectorFromString(@"onResp:");
    if (!response || ![response respondsToSelector:setError] || ![provider respondsToSelector:onResponse]) {
        LogEvent(@"result receiver unavailable");
        return;
    }
    // 0 = completed, -2 = cancelled, -1 = error. The sheet's outcome, not
    // merely its appearance, determines the app's share completion callback.
    int errorCode = error ? -1 : (completed ? 0 : -2);
    ((void (*)(id, SEL, int))objc_msgSend)(response, setError, errorCode);
    ((void (*)(id, SEL, id))objc_msgSend)(provider, onResponse, response);
}

@interface BLLinkItem : NSObject <UIActivityItemSource>
@property(nonatomic, strong) NSURL *url;
@property(nonatomic, copy) NSString *title;
@property(nonatomic, strong) UIImage *thumbnail;
@end
@implementation BLLinkItem
- (id)activityViewControllerPlaceholderItem:(UIActivityViewController *)controller { return self.url; }
- (id)activityViewController:(UIActivityViewController *)controller itemForActivityType:(UIActivityType)type { return self.url; }
- (NSString *)activityViewController:(UIActivityViewController *)controller subjectForActivityType:(UIActivityType)type { return self.title; }
- (UIImage *)activityViewController:(UIActivityViewController *)controller
             thumbnailImageForActivityType:(UIActivityType)type suggestedSize:(CGSize)size { return self.thumbnail; }
@end

static void PresentShare(id request, void (^completion)(BOOL), NSUInteger attempt) {
    UIViewController *controller = VisibleController();
    if ((!controller || !controller.view.window || controller.isBeingDismissed || controller.isBeingPresented) && attempt < 12) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_MSEC * 100), dispatch_get_main_queue(), ^{
            PresentShare(request, completion, attempt + 1);
        });
        return;
    }
    if (!controller || !controller.view.window || controller.isBeingDismissed || controller.isBeingPresented ||
        [controller isKindOfClass:UIActivityViewController.class]) {
        ShareInProgress = NO;
        LogEvent(@"presentation unavailable");
        if (completion) completion(NO);
        return;
    }
    NSArray *payload = BLShareItems(request);
    NSMutableArray *items = [NSMutableArray array];
    id message = BLObjectProperty(request, @"message");
    for (id item in payload) {
        if ([item isKindOfClass:NSURL.class]) {
            BLLinkItem *link = [BLLinkItem new];
            link.url = item;
            id title = BLObjectProperty(message, @"title");
            link.title = [title isKindOfClass:NSString.class] ? title : @"";
            NSData *thumb = BLObjectProperty(message, @"thumbData");
            if ([thumb isKindOfClass:NSData.class]) link.thumbnail = [UIImage imageWithData:thumb];
            [items addObject:link];
        } else if ([item isKindOfClass:NSData.class]) {
            UIImage *image = [UIImage imageWithData:item];
            if (image) [items addObject:image];
        } else [items addObject:item];
    }
    if (!items.count) {
        ShareInProgress = NO;
        LogEvent(@"unsupported or empty share payload");
        if (completion) completion(NO);
        return;
    }
    UIActivityViewController *sheet = [[UIActivityViewController alloc] initWithActivityItems:items applicationActivities:nil];
    sheet.completionWithItemsHandler = ^(UIActivityType type, BOOL completed, NSArray *returnedItems, NSError *error) {
        ShareInProgress = NO;
        LogEvent(error ? @"share error" : (completed ? @"share completed" : @"share cancelled"));
        NotifyShareResult(completed, error);
    };
    UIPopoverPresentationController *popover = sheet.popoverPresentationController;
    if (popover) {
        popover.sourceView = controller.view;
        CGRect bounds = controller.view.bounds;
        popover.sourceRect = CGRectMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds), 1, 1);
        popover.permittedArrowDirections = 0;
    }
    [controller presentViewController:sheet animated:YES completion:^{
        LogEvent(@"system share sheet presented");
        if (completion) completion(YES);
    }];
}

static void SendRequest(id api, SEL selector, id request, void (^completion)(BOOL)) {
    Class shareRequestClass = NSClassFromString(@"SendMessageToWXReq");
    if (!shareRequestClass || ![request isKindOfClass:shareRequestClass]) {
        OriginalSendRequest(api, selector, request, completion);
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        if (ShareInProgress) {
            if (completion) completion(NO);
            return;
        }
        ShareInProgress = YES;
        LogEvent(@"message share intercepted");
        PresentShare(request, completion, 0);
    });
}

// Keep the app's original internal router. Only the blue app's OS boundary
// translates between its private scheme and the original bilibili scheme.
static NSURL *Incoming(NSURL *url) { return BLRewriteScheme(url, PrivateScheme, @"bilibili"); }
static NSURL *Outgoing(NSURL *url) { return BLRewriteScheme(url, @"bilibili", PrivateScheme); }
static BOOL (*OriginalDelegateOpen)(id, SEL, UIApplication *, NSURL *, NSDictionary *);
static BOOL (*OriginalDelegateLegacy)(id, SEL, UIApplication *, NSURL *, NSString *, id);
static BOOL (*OriginalDelegateHandle)(id, SEL, UIApplication *, NSURL *);
static BOOL (*OriginalDelegateLaunch)(id, SEL, UIApplication *, NSDictionary *);
static BOOL DelegateOpen(id self, SEL cmd, UIApplication *app, NSURL *url, NSDictionary *options) {
    return OriginalDelegateOpen(self, cmd, app, Incoming(url), options);
}
static BOOL DelegateLegacy(id self, SEL cmd, UIApplication *app, NSURL *url, NSString *source, id annotation) {
    return OriginalDelegateLegacy(self, cmd, app, Incoming(url), source, annotation);
}
static BOOL DelegateHandle(id self, SEL cmd, UIApplication *app, NSURL *url) {
    return OriginalDelegateHandle(self, cmd, app, Incoming(url));
}
static BOOL DelegateLaunch(id self, SEL cmd, UIApplication *app, NSDictionary *options) {
    NSMutableDictionary *updated = [options mutableCopy];
    NSURL *url = options[UIApplicationLaunchOptionsURLKey];
    if ([url isKindOfClass:NSURL.class]) updated[UIApplicationLaunchOptionsURLKey] = Incoming(url);
    return OriginalDelegateLaunch(self, cmd, app, updated ?: options);
}
static void (*OriginalSetDelegate)(id, SEL, id);
static void SetDelegate(id self, SEL cmd, id delegate) {
    static Class patchedClass;
    Class cls = [delegate class];
    if (cls && !patchedClass) {
        patchedClass = cls;
        ReplaceMethod(cls, @selector(application:openURL:options:), (IMP)DelegateOpen, (IMP *)&OriginalDelegateOpen);
        ReplaceMethod(cls, @selector(application:openURL:sourceApplication:annotation:), (IMP)DelegateLegacy, (IMP *)&OriginalDelegateLegacy);
        ReplaceMethod(cls, @selector(application:handleOpenURL:), (IMP)DelegateHandle, (IMP *)&OriginalDelegateHandle);
        ReplaceMethod(cls, @selector(application:didFinishLaunchingWithOptions:), (IMP)DelegateLaunch, (IMP *)&OriginalDelegateLaunch);
    }
    OriginalSetDelegate(self, cmd, delegate);
}
static void (*OriginalOpen)(id, SEL, NSURL *, NSDictionary *, void (^)(BOOL));
static BOOL (*OriginalOpenLegacy)(id, SEL, NSURL *);
static BOOL (*OriginalCanOpen)(id, SEL, NSURL *);
static void Open(id self, SEL cmd, NSURL *url, NSDictionary *options, void (^completion)(BOOL)) {
    OriginalOpen(self, cmd, Outgoing(url), options, completion);
}
static BOOL OpenLegacy(id self, SEL cmd, NSURL *url) { return OriginalOpenLegacy(self, cmd, Outgoing(url)); }
static BOOL CanOpen(id self, SEL cmd, NSURL *url) { return OriginalCanOpen(self, cmd, Outgoing(url)); }

static BOOL InstallSendHook(void) {
    if (OriginalSendRequest) return YES;
    Class api = NSClassFromString(@"WXApi");
    return ReplaceMethod(object_getClass(api), NSSelectorFromString(@"sendReq:completion:"),
                         (IMP)SendRequest, (IMP *)&OriginalSendRequest);
}

__attribute__((constructor)) static void InstallBridge(void) {
    @autoreleasepool {
        BOOL installed = InstallSendHook();
        PrivateScheme = [NSBundle.mainBundle objectForInfoDictionaryKey:@"BLPrivateScheme"];
        if (PrivateScheme.length) {
            ReplaceMethod(UIApplication.class, @selector(setDelegate:), (IMP)SetDelegate, (IMP *)&OriginalSetDelegate);
            ReplaceMethod(UIApplication.class, @selector(openURL:options:completionHandler:), (IMP)Open, (IMP *)&OriginalOpen);
            ReplaceMethod(UIApplication.class, @selector(openURL:), (IMP)OpenLegacy, (IMP *)&OriginalOpenLegacy);
            ReplaceMethod(UIApplication.class, @selector(canOpenURL:), (IMP)CanOpen, (IMP *)&OriginalCanOpen);
        }
        LogEvent(installed ? @"share hook installed" : @"share hook MISSING");
        if (!installed) {
            // Some injected libraries initialize before the host's classes.
            // Install after startup in that case, before any user share action.
            [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidFinishLaunchingNotification
                object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
                    LogEvent(InstallSendHook() ? @"late share hook installed" : @"late share hook MISSING");
                }];
        }
    }
}
