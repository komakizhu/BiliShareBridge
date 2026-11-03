/*
 * Copyright (C) 2026 Komaki Zhu
 * SPDX-License-Identifier: GPL-3.0-only
 */
#import <Foundation/Foundation.h>

// These helpers deliberately depend only on Foundation, so real URL and payload
// handling can be exercised on the Mac without connecting to a phone.
FOUNDATION_EXPORT id BLObjectProperty(id object, NSString *name);
FOUNDATION_EXPORT NSURL *BLWebURL(NSString *value);
FOUNDATION_EXPORT NSArray *BLShareItems(id request);
FOUNDATION_EXPORT NSURL *BLRewriteScheme(NSURL *url, NSString *from, NSString *to);
