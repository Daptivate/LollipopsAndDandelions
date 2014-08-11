//
//  MPIGameManager.m
//  Multipeer.Instrument
//
//  Created by Kyle Beyer on 6/10/14.
//  Copyright (c) 2014 Kyle Beyer. All rights reserved.
//

#import "GameManager.h"
#import "Player.h"
#import "AudioManager.h"
#import "ActionMessage.h"
#import "MPIEventLogger.h"
#import "RestUtil.h"
#import <AVFoundation/AVFoundation.h>

@interface MPIGameManager()
@property (nonatomic, strong) AVCaptureSession *avSession;
@property (nonatomic, strong) MPIAudioManager *audioManager;
@property double lastTimestampSend;
@property (nonatomic, strong) NSTimer* heartbeatTimer;
@property (nonatomic, strong) NSTimer* sessionResetTimer;
@end


static int const kTimeSyncIterations = 10;
static int const kHearbeatIntervalSeconds = 2;
static int const kDiconnectedSessionResetTimeout = 10;

static BOOL const kEnableNodeVizApi = YES;
static NSString* const kApiHost = @"localhost:3000"; //@"k6beventlogger.herokuapp.com";

@implementation MPIGameManager

- (id)init {
    
    self = [super init];
    if (self) {
        // create local player and set display name
        _localPlayer = [[MPIPlayer alloc] init];
        _localPlayer.displayName = [[UIDevice currentDevice] name];
        // initial configuration
        [self configure];
        [self postSessionInfoToApi];
        [self sendPlayerToApi:_localPlayer isNew:YES];
    }
    return self;
}

- (void)configure {
    
    
    // single list with [peerID, state, lastHeartbeat] for each discovered peer
    _knownPlayers = [[NSMutableDictionary alloc] init];
    
    // configure MCSession handling
    _sessionController = [[MPISessionController alloc] initForPlayer:_localPlayer];
    self.sessionController.delegate = self;
    
    _audioManager = [[MPIAudioManager alloc] init];
    
    // setup self as motion manager delegate
    [MPIMotionManager instance].delegate = self;
}

+ (MPIGameManager *)instance
{
    static MPIGameManager* sharedInstance = nil;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[MPIGameManager alloc] init];
    });
    
    return sharedInstance;
}


#pragma mark - Memory management

- (void)dealloc
{
    // Nil out delegates
    _sessionController.delegate = nil;
    [MPIMotionManager instance].delegate = nil;
    
    _avSession = nil;
}

#pragma mark - Private class methods

- (MPIPlayer*) playerForPeerID:(MCPeerID*)peerID
{
    // default to logging if trying to lookup peer that doesn't exist
    return [self playerForPeerID:peerID logError:YES];
}
- (MPIPlayer*) playerForPeerID:(MCPeerID*)peerID logError:(BOOL)doLog
{
    NSEnumerator *enumerator = [_knownPlayers objectEnumerator];
    MPIPlayer* player;
    while ((player = [enumerator nextObject])) {
        if ([player.peerID isEqual:peerID]) {
            return player;
        }
    }
    
    if (doLog) { MPIError(@"No Player for PeerID: %@", peerID); }
    return nil;
}

#pragma mark - Time sync
// initiates simple algorithm to calculate system time delta with specified player
- (void)calculateTimeDeltaFromPeer:(id)nearbyPeerID
{
    // lookup player for peer
    MPIPlayer* player = [self playerForPeerID:nearbyPeerID];
    if (!player) { return; }
    
    // first clear latency array so that we can refresh values
    player.timeLatencySamples = [[NSMutableArray alloc] init];
    
    // send first message to kick off the process
    _lastTimestampSend = [[NSDate date] timeIntervalSince1970];
    [_sessionController sendTimestamp:[[NSNumber alloc] initWithDouble:_lastTimestampSend] toPeer:nearbyPeerID];
}
// returns the system time plus delta based on time sync process
- (NSDate*)currentTime
{
    return [NSDate dateWithTimeIntervalSinceNow:_timeDeltaSeconds];
}

- (BOOL)recievedTimestampFromPeer:(id)nearbyPeerID value:(NSNumber *)val
{
    // lookup player for peer
    MPIPlayer* player = [self playerForPeerID:nearbyPeerID];
    if (!player) { return YES; } // signal done on error
    
    double localTimestamp = [[NSDate date] timeIntervalSince1970];
    double serverTimestamp = [val doubleValue];
    
    // calculate current iteration latency
    double latency = (localTimestamp - _lastTimestampSend) / 2;
    [player.timeLatencySamples addObject:[[NSNumber alloc] initWithDouble:latency]];
    
    
    // check how many latency calculations we have
    if (player.timeLatencySamples.count >= kTimeSyncIterations) {
        // done with sync process ... calculate final offset
        double total;
        total = 0;
        for(NSNumber *value in player.timeLatencySamples){
            total+=[value floatValue];
        }
        
        // average latencies
        double averageLatency = total / player.timeLatencySamples.count;
        
        // save final offset
        _timeDeltaSeconds = serverTimestamp - localTimestamp + averageLatency;
        
        // save configuration to event logger
        [MPIEventLogger sharedInstance].timeDeltaSeconds = _timeDeltaSeconds;
        
        NSLog(@"TimeSync Complete. Delta: %f", _timeDeltaSeconds);
        
        // tell caller that we are done
        return YES;
        
    } else if (player.timeLatencySamples.count == 1) {
        
        // save first iteration offset
        _timeDeltaSeconds = serverTimestamp - localTimestamp + latency;
        
    }
    
    // save last send with initially calculated offset
    _lastTimestampSend = [[NSDate date] timeIntervalSince1970] + _timeDeltaSeconds;
    
    // send back to server
    [_sessionController sendTimestamp:[[NSNumber alloc] initWithDouble:_lastTimestampSend] toPeer:_sessionController.timeServerPeerID];
    
    //NSLog(@"local: %f, server: %f, latency: %f, lastSend: %f",
    //      localTimestamp, serverTimestamp, latency, _lastSendTimestamp);
    
    return NO;
    
}

#pragma mark - MotionManagerDelegate protocol conformance

- (void)attitudeChanged:(float)yaw pitch:(float)pitch roll:(float)roll
{
    // log for now ...
    NSLog(@"yaw: %f, pitch: %f, roll: %f", yaw, pitch, roll);
    // TODO: send message to peers
}

- (void)rotationChanged:(float)x y:(float)y z:(float)z
{
    // log for now ...
    NSLog(@"x: %f, y: %f, z: %f", x, y, z);
    // TODO: send message to peers
    
    // TEST: use y value to change display
    //[self requestColorChange:_sessionController.connectedPeers[0] value:[[NSNumber alloc] initWithFloat:y]];
}

#pragma mark - SessionControllerDelegate protocol conformance

- (void)session:(MPISessionController *)session didChangeState:(MPILocalSessionState)state
{
    MPIDebug(@"LocalSession changed state: %ld", state);
    switch(state){
        case MPILocalSessionStateNotCreated:
            _localSessionStateText = @"Not Created";
            break;
        case MPILocalSessionStateCreated:
            _localSessionStateText = @"Created";
            break;
        case MPILocalSessionStateAdvertising:
            _localSessionStateText = @"Advertising";
            break;
        case MPILocalSessionStateNotAdvertising:
            _localSessionStateText = @"Not Advertising";
            break;
        case MPILocalSessionStateBrowsing:
            _localSessionStateText = @"Browsing";
            break;
        case MPILocalSessionStateNotBrowsing:
            _localSessionStateText = @"Not Browsing";
            break;
        case MPILocalSessionStateConnected:
            _localSessionStateText = @"Connected";
            break;
    }
    // Ensure UI updates occur on the main queue.
    dispatch_async(dispatch_get_main_queue(), ^{
        [self notifyLocalSessionChange];
    });
}

- (void)peer:(MCPeerID *)nearbyPeerID didChangeState:(MPIPeerState)state
{
    MPIDebug(@"Peer (%@) changed state: %ld", nearbyPeerID.displayName, state);
    
    // lookup player for peer ... ignore not found error/logging
    MPIPlayer* player = [self playerForPeerID:nearbyPeerID logError:NO];
    if (!player) {
        // add as new known player
        MPIPlayer* newPlayer = [[MPIPlayer alloc] init];
        newPlayer.displayName = nearbyPeerID.displayName;
        newPlayer.peerID = nearbyPeerID;
        newPlayer.state = state;
        [_knownPlayers setObject:newPlayer forKey:newPlayer.playerID];
        
        [self postNewLinkToApi:newPlayer];
    } else {
        // update state
        player.state = state;
        
        // TEST: always send update to API on state change
        [self sendPlayerToApi:player isNew:NO];
    }
    
    if (state == MPIPeerStateDisconnected &&                // if state transitioned to disconnected
        player.lastHeartbeatSentToPeerAt != nil &&          // and there was previously a connection
        [self allPlayersAre:MPIPeerStateDisconnected]) {    // and there are no other connected peers
                                                            // then, queue up reset
        _sessionResetTimer = [NSTimer scheduledTimerWithTimeInterval:kDiconnectedSessionResetTimeout target:self
                                       selector:@selector(resetLocalSessionIfNoneConnected:) userInfo:nil repeats:NO];
    } else if (state != MPIPeerStateDisconnected) {
        // cancel reset timer ... if a peer transitions out of Disconnected state
        if (_sessionResetTimer) { [_sessionResetTimer invalidate]; _sessionResetTimer = nil; }
    }
    
    // Ensure UI updates occur on the main queue.
    dispatch_async(dispatch_get_main_queue(), ^{
        [self notifyPlayersChange];
    });
}


- (void)session:(MPISessionController *)session didReceiveAudioStream:(NSInputStream *)stream
{
    [_audioManager playStream:stream];
}

- (void)session:(MPISessionController *)session didReceiveAudioFileStream:(NSInputStream *)stream
{
    [_audioManager playFileStream:stream];
}

- (void)session:(MPISessionController *)session didReceiveAudioFileFrom:(NSString*)playerName atPath:(NSString*)filePath
{
    // add as new audio loop ... but don't play until receiving command
    [_audioManager addAudioLoop:playerName forURL:[NSURL fileURLWithPath:filePath] andPlay:YES];
}

- (void)session:(MPISessionController *)session allDisconnectedViaPeer:(MCPeerID*)peerID
{
    // queue up reset
    _sessionResetTimer = [NSTimer scheduledTimerWithTimeInterval:kDiconnectedSessionResetTimeout target:self
                                                     selector:@selector(resetLocalSessionIfNoneConnected:) userInfo:nil repeats:NO];
}



- (void)requestFlashChange:(id)peerID value:(NSNumber*)val {
    [_sessionController sendMessage:@"1" value:val toPeer:peerID];
}
- (void)requestSoundChange:(id)peerID value:(NSNumber*)val {
    [_sessionController sendMessage:@"2" value:val toPeer:peerID asReliable:NO];
}
- (void)requestColorChange:(id)peerID value:(NSNumber*)val {
    [_sessionController sendMessage:@"3" value:val toPeer:peerID asReliable:NO];
}
- (void)requestTimeSync:(id)peerID value:(NSNumber *)val {
    [_sessionController sendMessage:@"5" value:val toPeer:peerID];
}

- (void)handleActionRequest:(NSDictionary*)json type:(NSString*)type fromPeer:(id)fromPeerID {
    
    NSError *error = nil;
    if ([type isEqualToString:@"1"]) {
        
        MPIMessage *msg = [MTLJSONAdapter modelOfClass:[MPIMessage class] fromJSONDictionary:json error:&error];
        
        // change flash value
        [self toggleFlashlight];
        [_audioManager muteLoop:![msg.val boolValue] name:@"organ"];
        [_audioManager muteLoop:![msg.val boolValue] name:@"drums"];
        
        
    } else if ([type isEqualToString:@"2"]) {
        MPIMessage *msg = [MTLJSONAdapter modelOfClass:[MPIMessage class] fromJSONDictionary:json error:&error];
        // change sound of players
        self.volume = msg.val;
        //[self notifyVolumeChange];
        [_audioManager setLoopVolume:[msg.val floatValue] name:@"organ"];
        
        // set player loop volume
        // using local display name ... since file should be named based on recording from a different
        // device for my device
        //[_audioManager setLoopVolume:[msg.val floatValue] name:[_sessionController displayName]];
        
    } else if ([type isEqualToString:@"3"]) {
        MPIMessage *msg = [MTLJSONAdapter modelOfClass:[MPIMessage class] fromJSONDictionary:json error:&error];
        // change color of players
        self.color = msg.val;
        [self notifyColorChange];
        [_audioManager setLoopVolume:[msg.val floatValue] name:@"drums"];
        
        
        [_audioManager setLoopVolume:[msg.val floatValue]*1.5 name:_localPlayer.displayName];
        
    } else if ([type isEqualToString:@"4"]) {
        // timestamp handled by session controller
    } else if ([type isEqualToString:@"5"]) {
        // request for time sync handled by session controller
    } else if ([type isEqualToString:@"6"]) {
        
        MPISongInfoMessage *msg = [MTLJSONAdapter modelOfClass:[MPISongInfoMessage class] fromJSONDictionary:json error:&error];
        _lastSongMessage = msg;
        [self notifySongChange];
        
    } else if ([type isEqualToString:@"7"]) {
        
        MPIMessage *msg = [MTLJSONAdapter modelOfClass:[MPIMessage class] fromJSONDictionary:json error:&error];
        // start / stop play of recording
        [_audioManager muteLoop:![msg.val boolValue] name:_localPlayer.displayName];
        
    } else if ([type isEqualToString:@"8"]) {
        
        MPIMessage *msg = [MTLJSONAdapter modelOfClass:[MPIMessage class] fromJSONDictionary:json error:&error];
        
        // lookup player by peerID
        MPIPlayer* player = [self playerForPeerID:fromPeerID];
        if (!player) { return; }
        
        //
        // TODO: store this as local time ... or Game Time
        player.lastHeartbeatSentFromPeerAt = [NSDate dateWithTimeIntervalSince1970:[msg.val doubleValue]];
        player.lastHeartbeatReceivedFromPeerAt = [NSDate new];
            
        if (player.state == MPIPeerStateSyncingTime) {
            // on receipt of first heartbeat ... we know the time sync is complete
            // notify that peer state is connected and ready to engage
            [_sessionController.delegate peer:fromPeerID didChangeState:MPIPeerStateConnected];
            
        } else if (player.state == MPIPeerStateDisconnected) {
            
            //
            // TODO: reset session??
            // not yet... first try to self-heal connection by resetting the peer
            // who is able to send but is not receiving...
            //
            NSTimeInterval timeSinceLastSend = [player.lastHeartbeatReceivedFromPeerAt timeIntervalSinceDate:player.lastHeartbeatSentToPeerAt];
            
            
            MPIWarn(@"Heartbeat received from non-connected peer %@ in state %d. Seconds since last send:%f", fromPeerID, player.state, timeSinceLastSend);
            
            // reset if this happens for 3 heartbeats in a row
            if (timeSinceLastSend > 6.0f) {
                [self resetLocalSession];
            }
        }
        
        
        // only manually trigger change notice here...
        [self notifyPlayersChange];
    }
}

- (void)toggleFlashlight
{
    AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    
    if (device.isTorchAvailable && device.torchMode == AVCaptureTorchModeOff)
    {
        // Create an AV session
        AVCaptureSession *session = [[AVCaptureSession alloc] init];
        
        // Create device input and add to current session
        AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:device error: nil];
        [session addInput:input];
        
        // Create video output and add to current session
        AVCaptureVideoDataOutput *output = [[AVCaptureVideoDataOutput alloc] init];
        [session addOutput:output];
        
        // Start session configuration
        [session beginConfiguration];
        [device lockForConfiguration:nil];
        
        if([device isTorchModeSupported:AVCaptureTorchModeOn]){
            // Set torch to on
            [device setTorchMode:AVCaptureTorchModeOn];
        }
        
        [device unlockForConfiguration];
        [session commitConfiguration];
        
        // Start the session
        [session startRunning];
        
        // Keep the session around
        _avSession = session;
        
        //[output release];
    }
    else
    {
        [_avSession stopRunning];
        _avSession = nil;
    }
}

//
// TODO: switch to ReactiveCocoa already...
//
- (void) notifyLocalSessionChange {
    [[NSNotificationCenter defaultCenter] postNotificationName:@"localSessionStateChanged" object:self];
}
- (void) notifyPlayersChange {
    [[NSNotificationCenter defaultCenter] postNotificationName:@"playerListChanged" object:self];
}
- (void) notifyVolumeChange {
    [[NSNotificationCenter defaultCenter] postNotificationName:@"volumeChanged" object:self];
}
- (void) notifyColorChange {
    [[NSNotificationCenter defaultCenter] postNotificationName:@"colorChanged" object:self];
}
- (void) notifyAudioInChange {
    [[NSNotificationCenter defaultCenter] postNotificationName:@"audioInChanged" object:self];
}
- (void) notifySongChange {
    [[NSNotificationCenter defaultCenter] postNotificationName:@"songChanged" object:self];
}

- (void) startEcho:(NSOutputStream*)stream
{
    [_audioManager openMic:stream];
}
- (void) stopEcho
{
    [_audioManager closeMic];
}


- (void)startRecordMicFor:(NSString*)playerName {
    [_audioManager startRecordingToFile:[_audioManager recordingFilePathFor:playerName]];
}
- (void)stopRecordMicFor:(NSString*)playerName withPeer:(id)peerID {
    NSString* filePath = [_audioManager recordingFilePathFor:playerName];
    // tell audio manager to stop recording
    [_audioManager stopRecordingToFile:filePath];
    
    // send when file is done recording
    [_sessionController sendAudioFileAtPath:filePath toPeer:peerID];
    
    // auto-play there
    // NOTE: do this as part of file recieve ... since we need to wait for file transfer
    //[self startPlayRecordingFor:playerName onPeer:peerID];
    
    // auto-play here
    [self startPlayRecordingFor:playerName];
}

- (void)startPlayRecordingFor:(NSString*)playerID {
    NSString *filePath = [_audioManager recordingFilePathFor:playerID];
    [_audioManager startPlayingFromFile:filePath];
}

- (void)startStreamingRecordingTo:(id)peerID fromPlayerName:(NSString*)playerName {
    
    //[_sessionController sendAudioFileAtPath:[self recordingFilePathFor:playerName] toPeer:peerID];
    
    //
    // TODO: send message to start playing transfered audio
    //
    
    //NSOutputStream *stream = [_sessionController outputStreamForPeer:peerID withName:@"audio-file"];
    //[_audioManager startAudioFileStream:stream fromPath:[self recordingFilePathFor:playerName]];
}

- (void)stopStreamingRecordingFrom:(NSString*)playerName {
    [_audioManager stopAudioFileStreamFrom:[_audioManager recordingFilePathFor:playerName]];
}

- (void)stopPlayRecordingFor:(NSString *)playerID {
    [_audioManager stopPlayingFromFile];
}


- (void)startPlayRecordingFor:(NSString *)playerID onPeer:peerID {
    // send play command
    [_sessionController sendMessage:@"7" value:[[NSNumber alloc] initWithInt:1] toPeer:peerID];
}
- (void)stopPlayRecordingFor:(NSString *)playerID onPeer:peerID {
    // send stop command
    [_sessionController sendMessage:@"7" value:[[NSNumber alloc] initWithInt:0] toPeer:peerID];
}

- (void) changeReverb:(BOOL)on
{
    [_audioManager enableReverb:on];
}
- (void) changeLimiter:(BOOL)on
{
    [_audioManager enableLimiter:on];
}
- (void) changeExpander:(BOOL)on
{
    [_audioManager enableExpander:on];
}
- (void) changeRecordingGain:(float)val
{
    _audioManager.recordingGain = val;
}

- (void) startup
{
    [_sessionController startup];
    //[[MPIMotionManager instance] start];
    
    // try to send heartbeat to all connected peers
    _heartbeatTimer = [NSTimer scheduledTimerWithTimeInterval:kHearbeatIntervalSeconds target:self
                                                     selector:@selector(broadcastHeartbeat:) userInfo:nil repeats:YES];
}
- (void) shutdown
{
    [_sessionController shutdown];
    [_avSession stopRunning];
    _avSession = nil;
    [[MPIMotionManager instance] stop];
    
    [_knownPlayers removeAllObjects];
}

- (BOOL) allPlayersAre:(MPIPeerState)state
{
    NSEnumerator *enumerator = [_knownPlayers objectEnumerator];
    MPIPlayer* player;
    while ((player = [enumerator nextObject])) {
        if (player.state != state) { return NO; }
    }
    return YES;
}

- (void) resetLocalSessionIfNoneConnected:(NSTimer *)incomingTimer
{
    MPIDebug(@"Checking if all peers are disconnected");
    // make sure all known are not connected
    if ([self allPlayersAre:MPIPeerStateDisconnected]) {
    
        // if so ... reset known peers
        // TODO:
        
        
        // and local session
        [self resetLocalSession];
    }
    
}

- (void) resetLocalSession
{
    
    MPIDebug(@"Resetting local session.");
    
    // cancel reset timer
    if (_sessionResetTimer) { [_sessionResetTimer invalidate]; _sessionResetTimer = nil; }
    
    MPILocalSessionState oldSessionState = _sessionController.localSessionState;
    MPISessionController *oldSessionController = _sessionController;
    [oldSessionController stopAdvertising];
    [oldSessionController stopBrowsing];
    [_knownPlayers removeAllObjects];
    
    //
    // TODO: send remove to API
    //
    
    
    //
    // TEST: ... first try creating a new session controller
    //
    
    
    //
    // TODO: reset in current state ... without advertise delay
    // i.e. - if currently browsing ... start in browsing state
    // if currently advertising ... start in advertising state with delay
    //
    
    _sessionController = [[MPISessionController alloc] initForPlayer:_localPlayer withState:MPILocalSessionStateAdvertising];
    self.sessionController.delegate = self;
    
    // clear out previous session and known players
    //[oldSessionController shutdown];
    //oldSessionController = nil;
    
    [_sessionController startup];
    
    // send player update to API
    [self sendPlayerToApi:_localPlayer isNew:NO];
}


// every kHeartbeatIntervalSeconds ... to all peers
- (void) broadcastHeartbeat:(NSTimer *)incomingTimer
{
    double timestamp = [[NSDate date] timeIntervalSince1970];
    // NOTE: sending to each individually ... to enable better understanding of connection status via send msg error
    NSEnumerator *enumerator = [_knownPlayers objectEnumerator];
    MPIPlayer* player;
    while ((player = [enumerator nextObject])) {
        // send heartbeat to connected peers
        // TODO: ... or always try all??
        
        if (player.state != MPIPeerStateStale) {
            BOOL success = [_sessionController sendMessage:@"8" value:[[NSNumber alloc] initWithDouble:timestamp] toPeer:player.peerID asReliable:NO];
            if (!success) {
                // mark disconnected if hearbeat fails
                [_sessionController.delegate peer:player.peerID didChangeState:MPIPeerStateDisconnected];
            } else if (player.state != MPIPeerStateConnected) {
                // transition connected if not already
                [_sessionController.delegate peer:player.peerID didChangeState:MPIPeerStateConnected];
            }
            
            //always update last sent date on success
            if (success) { player.lastHeartbeatSentToPeerAt = [NSDate new]; }
        }
        
        // TEST: always send update to API on heartbeat attempt
        [self sendPlayerToApi:player isNew:NO];
    }
}

// one time ... on sync complete
- (void) startHeartbeatWithPeer:(id)peerID
{
    double timestamp = [[NSDate date] timeIntervalSince1970];
    [_sessionController sendMessage:@"8" value:[[NSNumber alloc] initWithDouble:timestamp] toPeer:peerID asReliable:NO];
    
    //
    // TODO: expect response ??
    // NO: ... for now we are just sending without expectation
    //
    
}

#pragma mark - helpers for REST API

- (void)postSessionInfoToApi
{
    if (!kEnableNodeVizApi) { return; }
    
    NSString* baseURL = [[NSString alloc] initWithFormat:@"http://%@/api/v1/", kApiHost];
    
    NSURL* url = [NSURL URLWithString:[baseURL stringByAppendingPathComponent:@"sessions"]]; //create url
    
    NSMutableDictionary* sessionInfo = [[NSMutableDictionary alloc] init];
    [sessionInfo setValue:_localPlayer.playerID forKey:@"session_id"];
    [sessionInfo setValue:_localPlayer.displayName forKey:@"display_name"];
    
    [[RestUtil sharedInstance] post:sessionInfo toUrl:url responseHandler:^(NSDictionary* dataJson) {
        MPIDebug(@"Resonpse from session post: %@", dataJson);
    }];
}

- (void)sendPlayerToApi:(MPIPlayer*)newPlayer isNew:(BOOL)isNew
{
    if (!kEnableNodeVizApi) { return; }
    
    // first post new node for player
    NSString* baseURL = [[NSString alloc] initWithFormat:@"http://%@/api/v1/", kApiHost];
    
    NSURL* url = [NSURL URLWithString:[baseURL stringByAppendingPathComponent:@"nodes"]]; //create url
    
    NSDictionary* playerJson = [MTLJSONAdapter JSONDictionaryFromModel:newPlayer];
    
    if (!isNew) {
        // create put url
        url = [url URLByAppendingPathComponent:newPlayer.mongoID];
        // send put/update request
        [[RestUtil sharedInstance] put:playerJson toUrl:url];
    } else {
        [[RestUtil sharedInstance] post:playerJson toUrl:url responseHandler:^(NSDictionary* dataJson) {
            
            NSError* parseError;
            MPIPlayer *pResponse = [MTLJSONAdapter modelOfClass:[MPIPlayer class] fromJSONDictionary:dataJson error:&parseError];
            if (parseError != nil) {
                MPIError(@"Error deserializing player response: %@", parseError);
                return;
            }
            MPIDebug(@"Response from player post: %@", [MTLJSONAdapter JSONDictionaryFromModel:pResponse]);
            
            // set generated mongo id
            newPlayer.mongoID = pResponse.mongoID;
            
        }];
    }
}

- (void)postNewLinkToApi:(MPIPlayer*)newPlayer
{
    if (!kEnableNodeVizApi) { return; }
    
    // first post new node for player
    [self sendPlayerToApi:newPlayer isNew:YES];
    
    // then, post link info between local player and new player
    NSString* baseURL = [[NSString alloc] initWithFormat:@"http://%@/api/v1/", kApiHost];
    NSURL* url = [NSURL URLWithString:[baseURL stringByAppendingPathComponent:@"links"]]; //create url
    
    NSMutableDictionary* linkInfo = [[NSMutableDictionary alloc] init];
    [linkInfo setValue:_localPlayer.playerID forKey:@"from_node_id"];
    [linkInfo setValue:newPlayer.playerID forKey:@"to_node_id"];
    [linkInfo setValue:[MPIPlayer peerStateToString:newPlayer.state] forKey:@"state"];
    
    [[RestUtil sharedInstance] post:linkInfo toUrl:url responseHandler:^(NSDictionary* dataJson) {
        MPIDebug(@"Resonpse from link post: %@", dataJson);
    }];
}


@end
