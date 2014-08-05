//
//  MPIPlayer.m
//  Multipeer.Instrument
//
//  Created by Kyle Beyer on 6/10/14.
//  Copyright (c) 2014 Kyle Beyer. All rights reserved.
//

#import "Player.h"

@implementation MPIPlayer

- (id)init {
    
    self = [super init];
    if (self) {
        // create unique id on construction
        _playerID = [[NSUUID UUID] UUIDString];
    }
    return self;
}

@end
