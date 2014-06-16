//
//  MPIEvent.m
//  Multipeer.Instrument
//
//  Created by Kyle Beyer on 6/16/14.
//  Copyright (c) 2014 Kyle Beyer. All rights reserved.
//

#import "MPIEvent.h"
#import "MPIEventLogger.h"
#import "MTLValueTransformer.h"

@implementation MPIEvent

+ (NSDateFormatter *)dateFormatter {
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    dateFormatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
    dateFormatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss'Z'";
    return dateFormatter;
}

+ (NSDictionary *)JSONKeyPathsByPropertyKey {
    return @{
             @"source": @"source",
             @"description": @"description",
             @"start": @"start",
             @"end": @"end",
             @"tags": @"tags",
             @"data": @"data",
             @"deviceID": @"deviceID"
             };
}

/*
 * Advanced init currently accepts all properties.
 * The log functions are overloaded to help create with default values
 *
 * @param source - string to identify the source of the Event
 * @param description - friendly display text for the Event
 */
- (id)init:(MPILoggerLevel)level
            source:(NSString*)source
            description:(NSString*)description
            tags:(NSArray*)tags
            start:(NSDate*)start
            end:(NSDate*)end
            data:(NSDictionary*)data
            deviceID:(NSString *)deviceID {
    
    self = [super init];
    if (self) {
        // initialize all properties
        _level = level;
        _source = source;
        _description = description;
        _tags = tags;
        _start = start;
        _end = end;
        _data = data;
        _deviceID = deviceID;
    }
    return self;
}

- (BOOL)isValid {
    return _source != nil && _start != nil && _description != nil;
}

@end
