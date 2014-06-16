//
//  MPIEvent.h
//  Multipeer.Instrument
//
//  Created by Kyle Beyer on 6/16/14.
//  Copyright (c) 2014 Kyle Beyer. All rights reserved.
//

#import "MTLModel.h"
#import "MTLJsonAdapter.h"

// placeholder ... defined in MPIEventLogger
typedef NS_ENUM(NSUInteger, MPILoggerLevel);

@interface MPIEvent : MTLModel<MTLJSONSerializing>

// logger level for which the event was created
@property (nonatomic, assign) MPILoggerLevel level;
// the device from which the event was created
@property (nonatomic, copy) NSString* deviceID;
// tags are used as non-herarchical categories for events
@property (nonatomic, copy) NSArray* tags;
// the description is used as display string and console text
@property (nonatomic, copy) NSString* description;
// the start time is when the event happened
@property (nonatomic, copy) NSDate* start;
// (optional) the end time is used to calculate duration where applicable
@property (nonatomic, copy) NSDate* end;
// any metadata (or custom details) for the event can be stored in the data property
@property (nonatomic, copy) NSDictionary* data;
// a string to identify the source of the event (e.g. - device name)
@property (nonatomic, copy) NSString* source;

// implement validation for event data
- (BOOL)isValid;

// overloaded init method to create MPIEvent from MPIEventLogger.log methods
- (id)init:(MPILoggerLevel)level
    source:(NSString*)source
description:(NSString*)description
      tags:(NSArray*)tags
     start:(NSDate*)start
       end:(NSDate*)end
      data:(NSDictionary*)data
  deviceID:(NSString*)deviceID;

@end
