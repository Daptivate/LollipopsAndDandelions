//
//  MPISessionController.h
//  Multipeer.Instrument
//
//  Created by Kyle Beyer on 6/10/14.
//  Copyright (c) 2014 Kyle Beyer. All rights reserved.
//

#import <MultipeerConnectivity/MultipeerConnectivity.h>
#import "Player.h"

// Custom states for the controller to abstract local MCSession behavior
typedef NS_ENUM(NSInteger, MPILocalSessionState) {
    MPILocalSessionStateNotCreated,
    MPILocalSessionStateCreated,
    MPILocalSessionStateAdvertising,
    MPILocalSessionStateNotAdvertising,
    MPILocalSessionStateBrowsing,
    MPILocalSessionStateNotBrowsing,
    MPILocalSessionStateConnected
};

@protocol MPISessionControllerDelegate;

/*!
 @class MPISessionController
 @abstract
 Manages the lifecycle of MCSession.
 Enables service Advertising and Browsing to be enabled or disabled.
 
 IMPORTANT: MCSessionDelegate calls occur on a private operation queue.
 To perform an action on a particular run loop or operation queue,
 its delegate method should explicitly dispatch or schedule that work
 */
@interface MPISessionController : NSObject <MCSessionDelegate, MCNearbyServiceBrowserDelegate, MCNearbyServiceAdvertiserDelegate>


- (instancetype)initForPlayer:(MPIPlayer*)player;

- (instancetype)initForPlayer:(MPIPlayer*)player withState:(MPILocalSessionState)state;

@property (readwrite) MPILocalSessionState localSessionState;  // track state of managed MCSession

@property (nonatomic, weak) id<MPISessionControllerDelegate> delegate;

// player for this device and session controller
// displayName and peerID are initialized in initForPlayer
@property (nonatomic, readonly) MPIPlayer* localPlayer;


// creates and returns stream for peer via current session
- (NSOutputStream *)outputStreamForPeer:(MCPeerID *)peer withName:(NSString*)streamName;

// Helper method for human readable printing of MCSessionState. This state is per peer.
- (NSString *)stringForPeerConnectionState:(MCSessionState)state;

// the peer used as reference time server
@property (strong, nonatomic) MCPeerID* timeServerPeerID;

// send local timestamp message to peer
- (void)sendTimestamp:(MCPeerID*)peer;
// send timestamp with value to peer
- (void)sendTimestamp:(NSNumber*)val toPeer:(MCPeerID*)peer;
// overloads for sending message with type and val to a single or multiple peers
- (BOOL)sendMessage:(NSString*)type value:(NSNumber*)val toPeer:(MCPeerID*)peer;
- (BOOL)sendMessage:(NSString*)type value:(NSNumber*)val toPeer:(MCPeerID*)peer asReliable:(BOOL)reliable;
- (BOOL)sendMessage:(NSString*)type value:(NSNumber*)val toPeers:(NSArray*)peers;
- (BOOL)sendMessage:(NSString*)type value:(NSNumber*)val toPeers:(NSArray*)peers asReliable:(BOOL)reliable;
- (BOOL)sendMessage:(id)msg toPeer:(MCPeerID*)peer;
- (BOOL)sendMessage:(id)msg toPeers:(NSArray*)peers;
- (BOOL)sendMessage:(id)msg toPeers:(NSArray*)peers asReliable:(BOOL)reliable;

// send audio file to peer
- (void)sendAudioFileAtPath:(NSString*)filePath toPeer:(id)peerID;

// advertiser and browser controller
- (void)startAdvertising;
- (void)stopAdvertising;
- (void)startBrowsing;
- (void)stopBrowsing;

// stop all multi-peer related sessions
- (void)startup;
- (void)shutdown;

@end

// Delegate methods for SessionController
@protocol MPISessionControllerDelegate <NSObject>

// Peer connection state changed - connecting, connected and disconnected peers changed
- (void)peer:(MCPeerID *)peerID didChangeState:(MPIPeerState)state;

// Local session changed state
- (void)session:(MPISessionController *)session didChangeState:(MPILocalSessionState)state;

// There are no more connected peers ... triggered via didChangeState
- (void)session:(MPISessionController *)session allDisconnectedViaPeer:(MCPeerID*)peerID;

// raw audio input ... e.g. - mic
- (void)session:(MPISessionController *)session didReceiveAudioStream:(NSInputStream *)stream;

// audio file stream
- (void)session:(MPISessionController *)session didReceiveAudioFileStream:(NSInputStream *)stream;

// recieved audio file
- (void)session:(MPISessionController *)session didReceiveAudioFileFrom:(MCPeerID*)peerID atPath:(NSString*)filePath;

@end

