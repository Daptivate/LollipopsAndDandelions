//
//  MPIPlayer.h
//  Multipeer.Instrument
//
//  Created by Kyle Beyer on 6/10/14.
//  Copyright (c) 2014 Kyle Beyer. All rights reserved.
//

//
// TODO: separate concerns ... importing this into data model is messy
// MCPeerID should be managed by Session Controller.
// MPIPeerState could be changed to PlayerState and defined here.
//
#import "SessionController.h"



@interface MPIPlayer : NSObject

// UUID for tracking player accross session resets
// valid for lifetime of GameManager
@property (readonly) NSString* playerID;

// name to use for display in UI
@property (readwrite) NSString* displayName;

// currently active session specific id
// this can be reset on diconnect/reconnection
// used for communicating via MCSession
@property (readwrite) MCPeerID* peerID;

// current state of peer connection
@property (readwrite) MPIPeerState state;

// timestamp that was received from sender
// on last receipt of hearbeat
@property (readwrite) NSDate* lastHeartbeatSentFromPeerAt;

// local timestamp of when heartbeat was received
// the difference of Sent & Received is approximation
// of the current latency between devices
@property (readwrite) NSDate* lastHeartbeatReceivedFromPeerAt;

// timestamp of last successful send of heartbeat to this peer
@property (readwrite) NSDate* lastHeartbeatSentToPeerAt;

// an array of samples from time sync process
// between time server and this device
// captured during time sync process on initial connection
@property (readwrite) NSMutableArray* timeLatencySamples;

@end