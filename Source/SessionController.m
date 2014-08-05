//
//  SessionController.m
//  Multipeer.Instrument
//
//  Created by Kyle Beyer on 6/10/14.
//  Copyright (c) 2014 Kyle Beyer. All rights reserved.
//

#import "SessionController.h"
#import "GameManager.h"
#import "Player.h"
#import "Message.h"
#import "MPIEventLogger.h"
#import <CommonCrypto/CommonDigest.h>

@interface MPISessionController () // Class extension

@property (readwrite) MPIPeerState myPeerState;             // track state of local peer

@property (nonatomic, strong) MCSession *session;
@property (nonatomic, strong) MCNearbyServiceAdvertiser *serviceAdvertiser;
@property (nonatomic, strong) MCNearbyServiceBrowser *serviceBrowser;

// timer for initial advertise ...
@property (nonatomic, strong) NSTimer* advertiseTimer;

// track start time of invitation process for specific peers
@property (nonatomic, strong) NSMutableDictionary* invitations;

@end

@implementation MPISessionController

static NSString * const kLogDefaultTag = @"SessionController";
static NSString * const kLocalPeerIDKey = @"mpi-local-peerid";
static NSString * const kMCSessionServiceType = @"mpi-shared";

static double const kInitialAdvertiseSeconds = 5.0f;

#pragma mark - Initializer

- (instancetype)initForPlayer:(MPIPlayer*)player
{
    self = [super init];
    
    if (self)
    {
        self = [self initForPlayer:player withState:MPILocalSessionStateCreated];
    }
    return self;
}

- (instancetype)initForPlayer:(MPIPlayer*)player withState:(MPILocalSessionState)state
{
    self = [super init];
    
    if (self)
    {
        // it is assumed that the player ID and displayName
        // have been initialized prior to calling this method
        _localPlayer = player;
        
        // default initial state
        _localSessionState = state;
        
        
        NSString *nameWithUUID = [[NSString alloc] initWithFormat:@"%@ <%@>", player.displayName, [[NSUUID UUID] UUIDString]];
        _localPlayer.peerID = [[MCPeerID alloc] initWithDisplayName:nameWithUUID];
        
        
        _invitations = [[NSMutableDictionary alloc] init];
        
        // check for request to start in a specific state
        switch (state){
            case MPILocalSessionStateAdvertising:
            case MPILocalSessionStateBrowsing:
                [self startupWithState:state];
                break;
        }
    }
    
    return self;
}


#pragma mark - Memory management

- (void)dealloc
{
    // Unregister for notifications on deallocation.
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    // Nil out delegates
    _session.delegate = nil;
    _serviceAdvertiser.delegate = nil;
    _serviceBrowser.delegate = nil;
}

#pragma mark - Public methods

- (void)sendTimestamp:(MCPeerID*)peer{
    // call overriden method
    [self sendTimestamp:[[NSNumber alloc] initWithDouble:[[NSDate date] timeIntervalSince1970]] toPeer:peer];
}
- (void)sendTimestamp:(NSNumber*)time toPeer:(MCPeerID*)peer{
    // call overriden method
    [self sendMessage:@"4" value:time toPeer:peer];
}

- (BOOL)sendMessage:(NSString*)type value:(NSNumber*)val toPeer:(MCPeerID*)peer {
    return [self sendMessage:type value:val toPeer:peer asReliable:YES];
}
- (BOOL)sendMessage:(NSString*)type value:(NSNumber*)val toPeer:(MCPeerID*)peer asReliable:(BOOL)reliable {
    
    // convert single peer to array
    NSArray *peers = [[NSArray alloc] initWithObjects:peer, nil];
    
    // call overriden method
    return [self sendMessage:type value:val toPeers:peers asReliable:reliable];
}

- (BOOL)sendMessage:(NSString*)type value:(NSNumber*)val toPeers:(NSArray *)peers{
    return [self sendMessage:type value:val toPeers:peers asReliable:YES];
}
- (BOOL)sendMessage:(NSString*)type value:(NSNumber*)val toPeers:(NSArray *)peers asReliable:(BOOL)reliable {
    NSDate* sendDt = [NSDate date];
    // create message object
    MPIMessage *msg = [[MPIMessage alloc] init];
    msg.type = type;
    msg.val = val;
    msg.createdAt = [[MPIEventLogger sharedInstance] timeWithOffset:sendDt];

    // use override
    return [self sendMessage:msg toPeers:peers];
}

- (BOOL) sendMessage:(id)msg toPeer:(MCPeerID *)peer {
    // convert single peer to array
    NSArray *peers = [[NSArray alloc] initWithObjects:peer, nil];
    
    // call overriden method
    return [self sendMessage:msg toPeers:peers];
}

- (BOOL) sendMessage:(id)msg toPeers:(NSArray *)peers {
    return [self sendMessage:msg toPeers:peers asReliable:YES];
}
- (BOOL) sendMessage:(id)msg toPeers:(NSArray *)peers asReliable:(BOOL)reliable {
     
    // serialize as JSON dictionary
    NSDictionary* json = [MTLJSONAdapter JSONDictionaryFromModel:msg];
    
    // convert to data object
    NSData *msgData = [NSKeyedArchiver archivedDataWithRootObject:[json copy]];
    NSError *error;
    // send message to specified peers ... using current session
    if (![self.session sendData:msgData
                        toPeers:peers
                       withMode:(reliable ? MCSessionSendDataReliable : MCSessionSendDataUnreliable)
                          error:&error]) {
        MPIError(@"[Error] sending data %@", error);
        
        // don't continue if there was an error
        // let caller determine whether this should cause transition in peer state
        return NO;
    }
    
    // log to server
    NSString* source = [[NSString alloc] initWithUTF8String:__PRETTY_FUNCTION__];
    [[MPIEventLogger sharedInstance] log:MPILoggerLevelInfo
                                  source:source
                             description:@"sending message"
                                    tags:[[NSArray alloc] initWithObjects:@"Message", nil]
                                   start:[NSDate date]
                                     end:nil
                                    data:json];
    return YES;
}


#pragma mark - Start or Stop session controller


- (void)startup
{
    [self startupWithState:MPILocalSessionStateCreated];
}
- (void)startupWithState:(MPILocalSessionState)state
{
    // Create the session that peers will be invited/join into.
    _session = [[MCSession alloc] initWithPeer:_localPlayer.peerID];
    self.session.delegate = self;
    
    MPIDebug(@"created session for: %@", _localPlayer.displayName);
    
    _localSessionState = state;
    
    switch(state){
        case MPILocalSessionStateCreated:
        case MPILocalSessionStateAdvertising:
            // advertise for a bit
            [self startAdvertising];
            // then switch to browse if no invite was received after
            _advertiseTimer = [NSTimer scheduledTimerWithTimeInterval:kInitialAdvertiseSeconds target:self
                                                             selector:@selector(advertiseTimedOut:) userInfo:nil repeats:NO];
            break;
            
        case MPILocalSessionStateBrowsing:
            [self startBrowsing];
            break;
    }
    
    
    [self.delegate session:self didChangeState:_localSessionState];
    
}

- (void) advertiseTimedOut:(NSTimer *)incomingTimer
{
    MPIDebug(@"Advertise timed out, starting browser.");
    // if invitation was not recieved ... and therefore the timer cancelled
    // then stop advertising and start browsing
    [self stopAdvertising];
    [self startBrowsing];
}

- (void)shutdown
{
    MPIDebug(@"teardown session for: %@", _localPlayer.displayName);
    
    [self.session disconnect];
    
    // clear out advertiser and browser ... if created
    _serviceBrowser = nil;
    _serviceAdvertiser = nil;
    
    // update local state
    _localSessionState = MPILocalSessionStateNotCreated;
    [self.delegate session:self didChangeState:_localSessionState];
}

#pragma mark - Control advertising and browsing

// advertiser and browser controller
- (void)startAdvertising
{
    // Create the service advertiser ... if not yet created
    if (_serviceAdvertiser == nil) {
        _serviceAdvertiser = [[MCNearbyServiceAdvertiser alloc] initWithPeer:_localPlayer.peerID
                                                               discoveryInfo:nil
                                                                 serviceType:kMCSessionServiceType];
        self.serviceAdvertiser.delegate = self;
        
        MPIDebug(@"created advertiser for: %@", _localPlayer.displayName);
    }
    
    MPIDebug(@"startAdvertising");
    [self.serviceAdvertiser startAdvertisingPeer];
    
    _localSessionState = MPILocalSessionStateAdvertising;
    [self.delegate session:self didChangeState:_localSessionState];
}
- (void)stopAdvertising
{
    MPIDebug(@"stopAdvertising");
    if (_serviceAdvertiser != nil) { [self.serviceAdvertiser stopAdvertisingPeer]; }
    
    // TODO: double check appropriate next state on advertise stop
    _localSessionState = MPILocalSessionStateNotAdvertising;
    [self.delegate session:self didChangeState:_localSessionState];
}
- (void)startBrowsing
{
    // Create the service browser ... if not yet created
    if (_serviceBrowser == nil) {
        _serviceBrowser = [[MCNearbyServiceBrowser alloc] initWithPeer:_localPlayer.peerID
                                                           serviceType:kMCSessionServiceType];
        self.serviceBrowser.delegate = self;
        
        MPIDebug(@"created browser for: %@", _localPlayer.displayName);
    }
    
    MPIDebug(@"startBrowsing");
    [self.serviceBrowser startBrowsingForPeers];
    
    _localSessionState = MPILocalSessionStateBrowsing;
    [self.delegate session:self didChangeState:_localSessionState];
}
- (void)stopBrowsing
{
    MPIDebug(@"stopBrowsing");
    if (_serviceBrowser != nil) { [self.serviceBrowser stopBrowsingForPeers]; }
    
    // TODO: double check appropriate next state on browsing stop
    _localSessionState = MPILocalSessionStateNotBrowsing;
    [self.delegate session:self didChangeState:_localSessionState];
}

#pragma mark - MCSessionDelegate protocol conformance

// See: http://stackoverflow.com/questions/18935288/why-does-my-mcsession-peer-disconnect-randomly
- (void) session:(MCSession*)session didReceiveCertificate:(NSArray*)certificate fromPeer:(MCPeerID*)peerID certificateHandler:(void (^)(BOOL accept))certificateHandler
{
    if (certificateHandler != nil) { certificateHandler(YES); }
}

- (void)session:(MCSession *)session peer:(MCPeerID *)peerID didChangeState:(MCSessionState)state
{
    
    MPIDebug(@"Peer [%@] changed state to %@.  There are now %lu connected.", peerID.displayName, [self stringForPeerConnectionState:state], (unsigned long)self.session.connectedPeers.count);
    
    switch (state)
    {
        case MCSessionStateConnecting:
        {
            [self.delegate peer:peerID didChangeState:MPIPeerStateDiscovered];
            break;
        }
            
        case MCSessionStateConnected:
        {
            NSDate* inviteBeganAt = _invitations[peerID.displayName];
            if (inviteBeganAt != nil) {
                NSArray* tags = [[NSArray alloc] initWithObjects:@"Invite", nil];
                NSString* description = [NSString stringWithFormat:@"Finished invite process with %@.", peerID.displayName];
                [[MPIEventLogger sharedInstance] info:@"Invitation" description:description tags:tags start:inviteBeganAt end:[[NSDate alloc] init]];
                
                // initiate time sync & save self as time server
                _timeServerPeerID = _localPlayer.peerID;
                [[MPIGameManager instance] requestTimeSync:peerID value:0];
                
                // change peer state to time syncing
                [self.delegate peer:peerID didChangeState:MPIPeerStateSyncingTime];
                
            } else {
                // change peer state to inite accepted
                [self.delegate peer:peerID didChangeState:MPIPeerStateInviteAccepted];
            }
            
            // check if local session state should change to created
            /* NOT CHANGING TO CONNECTED ... SO THAT WE PERSIST THE ADVERTISE vs. BROWSING state
            if (self.session.connectedPeers.count > 0) {
                _localSessionState = MPILocalSessionStateConnected;
                [self.delegate session:self didChangeState:_localSessionState];
            }
             */
            break;
        }
            
        case MCSessionStateNotConnected:
        {
            // update peer connection status
            [self.delegate peer:peerID didChangeState:MPIPeerStateDisconnected];
            
            // check if local session state should fall back to created
            if (self.session.connectedPeers.count <= 0) {
                //_localSessionState = MPILocalSessionStateCreated;
                //[self.delegate session:self didChangeState:_localSessionState];
                
                //
                //TEST: let GameManager handle this detection
                //
                // notify delegate that MCSession thinks there are no more connected peers
                //[self.delegate session:self allDisconnectedViaPeer:peerID];
            }
            break;
        }
    }
    
}

- (void)session:(MCSession *)session didReceiveData:(NSData *)data fromPeer:(MCPeerID *)nearbyPeerID
{
    // first unarchive
    id obj = [NSKeyedUnarchiver unarchiveObjectWithData:data];
    
    //
    // HACK, HACK, HACKY
    //
    // then deserialize as from JSON if NSDictionary
    if ([obj isKindOfClass:[NSDictionary class]]){
        
        NSString *msgType = obj[@"type"];
        // NEW: Log Message recieve event
        NSString* source = [[NSString alloc] initWithUTF8String:__PRETTY_FUNCTION__];
        NSString* action = @"UNKOWN";
        if ([msgType isEqualToString:@"1"]) {
            action = @"Flash";
        } else if ([msgType isEqualToString:@"2"]) {
            action = @"Volume";
        } else if ([msgType isEqualToString:@"4"]) {
            action = @"Time";
        } else if ([msgType isEqualToString:@"5"]) {
            action = @"Sync Request";
        } else if ([msgType isEqualToString:@"6"]) {
            action = @"Song Info";
        } else if ([msgType isEqualToString:@"7"]) {
            action = @"Recording play/stop";
        } else if ([msgType isEqualToString:@"8"]) {
            action = @"Heartbeat";
        }
        NSDate* start = [[MPIMessage dateFormatter] dateFromString:obj[@"createdAt"]];
        NSDate* end = [NSDate date];
        
        NSString* description = [NSString stringWithFormat:@"%@ sent %@", nearbyPeerID.displayName, action];
        NSArray* tags = [[NSArray alloc] initWithObjects:@"Message", action, nil];
        //MPIEventPersistence status =
        [[MPIEventLogger sharedInstance] debug:source description:description tags:tags start:start end:end data:obj];
        
        // handle sync and time messages differently
        if([action isEqualToString:@"Sync Request"]) {
            
            // save reference to peer which initiated sync
            _timeServerPeerID = nearbyPeerID;
            
            // initiate time sync with requestor
            [[MPIGameManager instance] calculateTimeDeltaFromPeer:nearbyPeerID];
            
            [self.delegate peer:nearbyPeerID didChangeState:MPIPeerStateSyncingTime];
            
        } else if([action isEqualToString:@"Time"]) {
            //
            // DANGER: what if peers have the same display name
            // HA! No longer a problem with unique ID generation
            if ([_timeServerPeerID.displayName isEqualToString:_localPlayer.peerID.displayName]) {
                // this is the time server ... so just reply with timestamp
                [self sendTimestamp:nearbyPeerID];
                
            } else {
                // this is peer that is requesting sync
                BOOL isDone = [[MPIGameManager instance] recievedTimestampFromPeer:nearbyPeerID value:0];
                if (isDone) {
                    [self.delegate peer:nearbyPeerID didChangeState:MPIPeerStateConnected];
                    
                    // now start heartbeat
                    [[MPIGameManager instance] startHeartbeatWithPeer:nearbyPeerID];
                }
                
            }
        } else {
            // default is to let the game manager handle the message
            [[MPIGameManager instance] handleActionRequest:obj type:msgType fromPeer:nearbyPeerID];
        }
        
    }
    
}

- (void)session:(MCSession *)session didStartReceivingResourceWithName:(NSString *)resourceName fromPeer:(MCPeerID *)peerID withProgress:(NSProgress *)progress
{
    MPIDebug(@"didStartReceivingResourceWithName [%@] from %@ with progress [%@]", resourceName, peerID.displayName, progress);
}

- (void)session:(MCSession *)session didFinishReceivingResourceWithName:(NSString *)resourceName fromPeer:(MCPeerID *)fromPeerID atURL:(NSURL *)localURL withError:(NSError *)error
{
    MPIDebug(@"didFinishReceivingResourceWithName [%@] from %@", resourceName, fromPeerID.displayName);
    
    // If error is not nil something went wrong
    if (error)
    {
        MPIError(@"Error [%@] receiving resource from %@ ", [error localizedDescription], fromPeerID.displayName);
    }
    else
    {
        // No error so this is a completed transfer.
        // The resources is located in a temporary location and should be copied to a permenant location immediately.
        // Write to documents directory
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *copyPath = [NSString stringWithFormat:@"%@/%@", [paths firstObject], resourceName];
        NSError* error;
        
        
        //
        // TODO: verify this works if the file does not exist yet
        //
        NSURL* resultingURL;
        if (![[NSFileManager defaultManager] replaceItemAtURL:[NSURL fileURLWithPath:copyPath] withItemAtURL:localURL backupItemName:@"audiofile-backup" options:NSFileManagerItemReplacementUsingNewMetadataOnly resultingItemURL:&resultingURL error:&error])
        {
            MPIError(@"Error copying resource to documents directory (%@) [%@]", copyPath, error);
        }
        else
        {
            // Get a URL for the path we just copied the resource to
            MPIDebug(@"url = %@, copyPath = %@", resultingURL, copyPath);
            
            // tell game manager about it .. should use self ID ... since it was for self
            [self.delegate session:self didReceiveAudioFileFrom:_localPlayer.peerID atPath:copyPath];
        }
    }
}

// Streaming API not utilized in this sample code
- (void)session:(MCSession *)session didReceiveStream:(NSInputStream *)stream withName:(NSString *)streamName fromPeer:(MCPeerID *)peerID
{
    MPIDebug(@"didReceiveStream %@ from %@", streamName, peerID.displayName);
    if ([streamName isEqualToString:@"mic"]) {
        [self.delegate session:self didReceiveAudioStream:stream];
    } else if ([streamName isEqualToString:@"audio-file"]) {
        [self.delegate session:self didReceiveAudioFileStream:stream];
    }
}

- (NSOutputStream *)outputStreamForPeer:(MCPeerID *)peer withName:(NSString*)streamName
{
    NSError *error;
    NSOutputStream *stream = [self.session startStreamWithName:streamName toPeer:peer error:&error];
    
    if (error) {
        MPIError(@"Error: %@", [error userInfo].description);
    }
    
    return stream;
}

- (void)sendAudioFileAtPath:(NSString*)filePath toPeer:(id)peerID
{
    NSURL *fileURL = [NSURL fileURLWithPath:filePath];
    MPIDebug(@"Attempting send for file at %@", filePath);
    
    //
    // TODO: hookup progress to UI
    //
    NSProgress *progress =
        [self.session sendResourceAtURL:fileURL
                               withName:[fileURL lastPathComponent]
                                 toPeer:peerID
                  withCompletionHandler:^(NSError *error)
        {
            if (error) { MPIError(@"[Error sending audio file] %@", error); return; }
            MPIDebug(@"Done sending file: %@", filePath);
        }];
}

#pragma mark - MCNearbyServiceBrowserDelegate protocol conformance

// Found a nearby advertising peer
- (void)browser:(MCNearbyServiceBrowser *)browser foundPeer:(MCPeerID *)nearbyPeerID withDiscoveryInfo:(NSDictionary *)info
{
    NSString *remotePeerName = nearbyPeerID.displayName;
    MPIDebug(@"Browser found nearbyPeer (name: %@)", remotePeerName);
    [self.delegate peer:nearbyPeerID didChangeState:MPIPeerStateDiscovered];
    
    //
    // TODO: are there other condition under which invitation should not be sent??
    //
    if (self.session != nil && _localSessionState != MPILocalSessionStateNotCreated) {
        MPIDebug(@"Inviting %@", remotePeerName);
        
        // save invitation start for this peer
        _invitations[remotePeerName] = [[NSDate alloc] init];
        
        [browser invitePeer:nearbyPeerID toSession:self.session withContext:nil timeout:20.0];
        
        [self.delegate peer:nearbyPeerID didChangeState:MPIPeerStateInvited];
    }
    else {
        MPIDebug(@"Session not ready. Not inviting foundPeer: %@", remotePeerName);
    }
}

- (NSString*)printSessionConnectedPeers
{
    NSString* output = @"";
    for (int i = 0; i < self.session.connectedPeers.count; i++) {
        MCPeerID* peerID = self.session.connectedPeers[i];
        output = [output stringByAppendingString:peerID.displayName];
    }
    return output;
}

- (void)browser:(MCNearbyServiceBrowser *)browser lostPeer:(MCPeerID *)peerID
{
    MPIDebug(@"lostPeer %@. session.connectedPeers: %@", peerID.displayName, [self printSessionConnectedPeers]);
    
    // update peer connection state
    [self.delegate peer:peerID didChangeState:MPIPeerStateStale];
}

- (void)browser:(MCNearbyServiceBrowser *)browser didNotStartBrowsingForPeers:(NSError *)error
{
    MPIDebug(@"didNotStartBrowsingForPeers: %@", error);
    
    _localSessionState = MPILocalSessionStateNotBrowsing;
    [self.delegate session:self didChangeState:_localSessionState];
}

#pragma mark - MCNearbyServiceAdvertiserDelegate protocol conformance

- (void)advertiser:(MCNearbyServiceAdvertiser *)advertiser didReceiveInvitationFromPeer:(MCPeerID *)peerID withContext:(NSData *)context invitationHandler:(void(^)(BOOL accept, MCSession *session))invitationHandler
{
    MPIDebug(@"didReceiveInvitationFromPeer %@", peerID.displayName);
    
    if (_advertiseTimer) {
        MPIDebug(@"INVALIDATING ADVERTISE TIMER");
        // cancel advertise timer on receipt of invitation
        [_advertiseTimer invalidate];
        _advertiseTimer = nil;
    }
    
    //
    // Only accept if not already in session.
    // This is to prevent multiple networks from being created.
    //
    
    if (!self.session) {
        MPIError(@"SESSION is NULL for receipt of invitation from %@.  Me: %@", peerID.displayName, _localPlayer.peerID.displayName);
        return;
    }
    
    if (self.session.connectedPeers.count == 0) {
        invitationHandler(YES, self.session);
        // update peer state
        [self.delegate peer:peerID didChangeState:MPIPeerStateInviteAccepted];
    } else {
        MPIDebug(@"NOT accepting invitation from %@ since there are already %lu connected peers.", peerID.displayName, (unsigned long)self.session.connectedPeers.count);
        invitationHandler(NO, self.session);
        // update peer state
        [self.delegate peer:peerID didChangeState:MPIPeerStateInviteDeclined];
    }

}

- (void)advertiser:(MCNearbyServiceAdvertiser *)advertiser didNotStartAdvertisingPeer:(NSError *)error
{
    MPIWarn(@"didNotStartAdvertisingForPeers: %@", error);
    
    _localSessionState = MPILocalSessionStateNotAdvertising;
    [self.delegate session:self didChangeState:_localSessionState];
}

//
// TODO: get rid of this .. only used for logging
//
- (NSString *)stringForPeerConnectionState:(MCSessionState)state
{
    switch (state) {
        case MCSessionStateConnected:
            return @"Connected";
            
        case MCSessionStateConnecting:
            return @"Connecting";
            
        case MCSessionStateNotConnected:
            return @"Not Connected";
    }
}

@end
