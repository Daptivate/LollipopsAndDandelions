//
//  MPIGameManager.h
//  Multipeer.Instrument
//
//  Created by Kyle Beyer on 6/10/14.
//  Copyright (c) 2014 Kyle Beyer. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SessionController.h"
#import "MPISongInfoMessage.h"
#import "MPIMotionManager.h"
#import "Player.h"


@interface MPIGameManager : NSObject<MPISessionControllerDelegate, MPIMotionManagerDelegate>

+ (MPIGameManager*)instance;

// player for this device
@property (readonly) MPIPlayer* localPlayer;

// currently active session controller for this device
@property (strong, nonatomic) MPISessionController *sessionController;

// the time offset from 'server' or reference player acting as 'time server'
@property (nonatomic) double timeDeltaSeconds;

// initiates simple algorithm to calculate system time delta with specified peer
- (void)calculateTimeDeltaFromPeer:(id)nearbyPeerID;
// returns the system time plus delta based on time sync process
- (NSDate*)currentTime;

// contains list of Player objects for any known peers
@property (nonatomic, readonly) NSMutableDictionary *knownPlayers;

@property (readwrite) BOOL enableVizApi;
@property (readwrite) NSNumber* volume;
@property (readwrite) NSNumber* color;
@property (readwrite) MPISongInfoMessage *lastSongMessage;
@property (readwrite) NSString* localSessionStateText;

- (void)requestFlashChange:(id)playerID value:(NSNumber*)val;
- (void)requestSoundChange:(id)playerID value:(NSNumber*)val;
- (void)requestColorChange:(id)playerID value:(NSNumber*)val;
- (void)requestTimeSync:(id)playerID value:(NSNumber*)val;

// handles time sync process
// @return NO if timesync should continue, YES if it is complete
- (BOOL)recievedTimestampFromPeer:(id)nearbyPeerID value:(NSNumber *)val;

- (void)handleActionRequest:(NSDictionary*)json type:(NSString*)type fromPeer:(id)fromPeerID;

- (void)startPlayRecordingFor:(NSString*)playerID;
- (void)startRecordMicFor:(NSString*)playerID;
- (void)stopPlayRecordingFor:(NSString*)playerID;
- (void)stopRecordMicFor:(NSString*)playerID withPeer:(id)peerID;


- (void)stopPlayRecordingFor:(NSString*)playerID onPeer:(id)peerID;
- (void)startPlayRecordingFor:(NSString*)playerID onPeer:(id)peerID;


- (void)startStreamingRecordingTo:(id)peerID fromPlayerName:(NSString*)playerName;
- (void)stopStreamingRecordingFrom:(NSString*)playerName;

- (void)startEcho:(NSOutputStream*)stream;
- (void)stopEcho;

- (void)changeReverb:(BOOL)on;
- (void)changeLimiter:(BOOL)on;
- (void)changeExpander:(BOOL)on;
- (void)changeRecordingGain:(float)val;

- (void)startup;
- (void)shutdown;

- (void)resetLocalSession;

- (void)startHeartbeatWithPeer:(id)peerID;
@end
