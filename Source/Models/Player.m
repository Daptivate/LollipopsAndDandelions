//
//  MPIPlayer.m
//  Multipeer.Instrument
//
//  Created by Kyle Beyer on 6/10/14.
//  Copyright (c) 2014 Kyle Beyer. All rights reserved.
//

#import "Player.h"
#import "Message.h"
#import <MultipeerConnectivity/MCPeerID.h>
#import "MTLValueTransformer.h"

@implementation MPIPlayer

- (id)init {
    
    self = [super init];
    if (self) {
        // create unique id on construction
        _playerID = [[NSUUID UUID] UUIDString];
    }
    return self;
}

- (void)setState:(MPIPeerState)state
{
    _state = state;
    _stateText = [MPIPlayer peerStateToString:state];
}

+ (NSDateFormatter *)dateFormatter {
    return [MPIMessage dateFormatter];
}

+ (NSString*)peerStateToString:(MPIPeerState)state
{
    NSString* stateText;
    switch(state) {
        case MPIPeerStateDiscovered:
            stateText = @"Discovered";
            break;
        case MPIPeerStateInvited:
            stateText = @"Invited";
            break;
        case MPIPeerStateInviteAccepted:
            stateText = @"Invite Accepted";
            break;
        case MPIPeerStateInviteDeclined:
            stateText = @"Invite Declined";
            break;
        case MPIPeerStateSyncingTime:
            stateText = @"Syncing Time";
            break;
        case MPIPeerStateConnected:
            stateText = @"Connected";
            break;
        case MPIPeerStateStale:
            stateText = @"Offline";
            break;
        case MPIPeerStateDisconnected:
            stateText = @"Disconnected";
            break;
    }
    return stateText;
}
+ (MPIPeerState)peerStateFromString:(NSString*)str
{
    if ([str isEqualToString:@"Discovered"]) {
        return MPIPeerStateDiscovered;
    } else if ([str isEqualToString:@"Invited"]) {
        return MPIPeerStateInvited;
    } else if ([str isEqualToString:@"Invite Accepted"]) {
        return MPIPeerStateInviteAccepted;
    } else if ([str isEqualToString:@"Invite Declined"]) {
        return MPIPeerStateInviteDeclined;
    } else if ([str isEqualToString:@"Syncing Time"]) {
        return MPIPeerStateSyncingTime;
    } else if ([str isEqualToString:@"Connected"]) {
        return MPIPeerStateConnected;
    } else if ([str isEqualToString:@"Offline"]) {
        return MPIPeerStateStale;
    } else if ([str isEqualToString:@"Disconnected"]) {
        return MPIPeerStateDisconnected;
    }
    return MPIPeerStateDiscovered;
}

+ (NSValueTransformer *)peerIDJSONTransformer {
    return [MTLValueTransformer reversibleTransformerWithForwardBlock:^(NSString *str) {
        return [[MCPeerID alloc] initWithDisplayName:str];
    } reverseBlock:^(MCPeerID *peerID) {
        return [peerID displayName];
    }];
}
+ (NSValueTransformer *)lastHeartbeatSentFromPeerAtJSONTransformer {
    return [MTLValueTransformer reversibleTransformerWithForwardBlock:^(NSString *str) {
        return [self.dateFormatter dateFromString:str];
    } reverseBlock:^(NSDate *date) {
        return [self.dateFormatter stringFromDate:date];
    }];
}
+ (NSValueTransformer *)lastHeartbeatReceivedFromPeerAtJSONTransformer {
    return [MTLValueTransformer reversibleTransformerWithForwardBlock:^(NSString *str) {
        return [self.dateFormatter dateFromString:str];
    } reverseBlock:^(NSDate *date) {
        return [self.dateFormatter stringFromDate:date];
    }];
}
+ (NSValueTransformer *)lastHeartbeatSentToPeerAtJSONTransformer {
    return [MTLValueTransformer reversibleTransformerWithForwardBlock:^(NSString *str) {
        return [self.dateFormatter dateFromString:str];
    } reverseBlock:^(NSDate *date) {
        return [self.dateFormatter stringFromDate:date];
    }];
}

+ (NSDictionary *)JSONKeyPathsByPropertyKey {
    return @{
             @"playerID": @"_id",
             @"displayName": @"displayName",
             @"peerID": @"peerID",
             @"stateText": @"stateText",
             @"lastHeartbeatSentFromPeerAt": @"lastHeartbeatSentFromPeerAt",
             @"lastHeartbeatReceivedFromPeerAt": @"lastHeartbeatReceivedFromPeerAt",
             @"lastHeartbeatSentToPeerAt": @"lastHeartbeatSentToPeerAt",
             @"timeLatencySamples": @"timeLatencySamples"
             };
}

@end
