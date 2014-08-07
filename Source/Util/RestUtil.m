//
//  RestUtil.m
//  Multipeer.Instrument
//
//  Created by Kyle Beyer on 8/6/14.
//  Copyright (c) 2014 Kyle Beyer. All rights reserved.
//

#import "RestUtil.h"

@implementation RestUtil


- (id)init {
    self = [super init];
    if (self) {
    }
    return self;
}


+ (RestUtil *)sharedInstance
{
    static RestUtil* sharedInstance = nil;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[RestUtil alloc] init];
    });
    
    return sharedInstance;
}


- (void)send:(NSDictionary*)jsonData
       toUrl:(NSURL*)apiUrl
  withMethod:(NSString*)httpMethod
completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler
{
    
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:apiUrl];
    request.HTTPMethod = httpMethod;
    
    //create data via dictionary
    NSData* data = [NSJSONSerialization dataWithJSONObject:jsonData options:0 error:NULL];
    request.HTTPBody = data;
    
    //set content type
    [request addValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    
    // TEST : some of the request seem to be dropped ... testing with new session every time
    NSURLSessionConfiguration* config = [NSURLSessionConfiguration defaultSessionConfiguration];
    NSURLSession* urlSession = [NSURLSession sessionWithConfiguration:config];
    
    NSURLSessionDataTask* dataTask = [urlSession dataTaskWithRequest:request completionHandler:completionHandler];
    
    
    [dataTask resume];
}

- (void)post:(NSDictionary*)jsonData toUrl:(NSURL*)apiUrl responseHandler:(void (^)(NSData* data))responseHandler {
    [self send:jsonData toUrl:apiUrl withMethod:@"POST" completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (!error) {
            // on success ... send data back to handler
            responseHandler(data);
        } else {
            MPIError(@"Error posting to API. %@", error);
        }
    }];
}

- (void)put:(NSDictionary*)jsonData toUrl:(NSURL*)apiUrl {
    [self send:jsonData toUrl:apiUrl withMethod:@"PUT" completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (!error) {
            //NSArray* responseArray = @[[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL]];
            //NSLog(@"request completed");
        } else {
            MPIError(@"Error sending PUT to API. %@", error);
        }
    }];
}



@end