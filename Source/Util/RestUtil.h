//
//  RestUtil.h
//  Multipeer.Instrument
//
//  Created by Kyle Beyer on 8/6/14.
//  Copyright (c) 2014 Kyle Beyer. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface RestUtil : NSObject


+(RestUtil*)sharedInstance;

- (void)post:(NSDictionary*)jsonData toUrl:(NSURL*)apiUrl responseHandler:(void (^)(NSDictionary* dataJson))responseHandler;

- (void)put:(NSDictionary*)jsonData toUrl:(NSURL*)apiUrl;

@end
