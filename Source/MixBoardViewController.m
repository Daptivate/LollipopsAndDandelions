//
//  MPIMixBoardViewController.m
//  Multipeer.Instrument
//
//  Created by Kyle Beyer on 6/10/14.
//  Copyright (c) 2014 Kyle Beyer. All rights reserved.
//


#import "MixBoardViewController.h"
#import "MixBoardTableCell.h"
#import "GameManager.h"
#import "Player.h"


#import "UIActionSheet+Blocks.h"

@interface MPIMixBoardViewController ()

@property (strong, nonatomic) AVAudioPlayer *audioPlayer;

@end


@implementation MPIMixBoardViewController


- (BOOL)prefersStatusBarHidden{ return YES; }


- (void)viewDidLoad
{
    [super viewDidLoad];
    [self setNeedsStatusBarAppearanceUpdate];
    
    
    // configure changes to listen to
    
    
    // listen for session state change
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(localSessionStateChanged) name:@"localSessionStateChanged" object:nil];
    // listen for players change
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playerListChanged) name:@"playerListChanged" object:nil];
    // listen for audio change
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(volumeChanged) name:@"volumeChanged" object:nil];
    // listen for color change
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(colorChanged) name:@"colorChanged" object:nil];
    // listen for audio input stream
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(audioInChanged) name:@"audioInChanged" object:nil];
    
    // configure audio player
    [self configureAudio];
    
    // set name
    _nameLabel.text = [MPIGameManager instance].sessionController.displayName;
    
    // timer for updating clock
    [NSTimer scheduledTimerWithTimeInterval:0.1 target:self selector:@selector(timerTick:) userInfo:nil repeats:YES];
    
}

- (void)timerTick:(NSTimer *)timer {
    
    static NSDateFormatter *dateFormatter;
    if (!dateFormatter) {
        dateFormatter = [[NSDateFormatter alloc] init];
        dateFormatter.dateFormat = @"hh:mm:ss.SSS";
    }
    _timeLabel.text = [dateFormatter stringFromDate:[NSDate date]];
    _timeWithOffsetLabel.text = [dateFormatter stringFromDate:[MPIGameManager instance].currentTime];
}

- (void)configureAudio
{
    NSURL *url = [NSURL fileURLWithPath:[[NSBundle mainBundle]
                                         pathForResource:@"Organ Run"
                                         ofType:@"m4a"]];
    
    NSError *error;
    _audioPlayer = [[AVAudioPlayer alloc]
                    initWithContentsOfURL:url
                    error:&error];
    if (error)
    {
        NSLog(@"Error in audioPlayer: %@",
              [error localizedDescription]);
    } else {
        _audioPlayer.delegate = self;
        [_audioPlayer prepareToPlay];
    }
}

- (void)volumeChanged{
    // Ensure UI updates occur on the main queue.
    dispatch_async(dispatch_get_main_queue(), ^{
        if (_audioPlayer != nil)
        {
            
            _audioPlayer.volume = [[[MPIGameManager instance] volume] floatValue];
            
            if (!_audioPlayer.isPlaying) {
                [_audioPlayer play];
            }
        }
    });
}
- (void)colorChanged{
    // Ensure UI updates occur on the main queue.
    dispatch_async(dispatch_get_main_queue(), ^{
        self.view.alpha = [[[MPIGameManager instance] color] floatValue];
    });
}

- (void)playerListChanged
{
    // Ensure UI updates occur on the main queue.
    dispatch_async(dispatch_get_main_queue(), ^{
        [_participantTableView reloadData];
    });
}

- (void)localSessionStateChanged
{
    // Ensure UI updates occur on the main queue.
    dispatch_async(dispatch_get_main_queue(), ^{
        _localSessionStateLabel.text = [MPIGameManager instance].localSessionStateText;
    });
}

- (void)audioInChanged
{
    // Ensure UI updates occur on the main queue.
    dispatch_async(dispatch_get_main_queue(), ^{
        NSLog(@"SONG SELECTION DISABLED");
        //[[[MPIGameManager instance] audioInStream] start];
    });
}

#pragma mark - Memory management

- (void)dealloc
{
    // Nil out delegates
    _audioPlayer.delegate = nil;
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    // Return the number of sections.
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    // Return the number of rows in the section.
    return [MPIGameManager instance].knownPeers.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *CellIdentifier = @"PlayerCell";
    MPIMixBoardTableCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier forIndexPath:indexPath];
    
    NSEnumerator *peerEnumerator = [[MPIGameManager instance].knownPeers objectEnumerator];
    PeerInfo* info;
    int index = 0;
    while ((info = [peerEnumerator nextObject])) {
        // break when we find the right item based on index
        if (indexPath.row == index) { break; }
        index++;
    }
    if (info)
    {
        cell.playerID = info.peerID;
        cell.nameLabel.text = info.peerID.displayName;
        
        NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
        dateFormatter.dateFormat = @"hh:mm:ss.SSS";
        cell.lastHeartbeatTimeLabel.text = [dateFormatter stringFromDate:info.lastHeartbeat];
        
        // disable unless connected
        [cell.soundSlider setEnabled:NO];
        [cell.colorSlider setEnabled:NO];
        [cell.flashSwitch setEnabled:NO];
        [cell.recordButton setEnabled:NO];
        [cell.playThereButton setEnabled:NO];
        
        NSString* stateText;
        switch(info.state) {
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
                [cell.soundSlider setEnabled:YES];
                [cell.colorSlider setEnabled:YES];
                [cell.flashSwitch setEnabled:YES];
                [cell.recordButton setEnabled:YES];
                [cell.playThereButton setEnabled:YES];
                break;
            case MPIPeerStateStale:
                stateText = @"Offline";
                break;
            case MPIPeerStateDisconnected:
                stateText = @"Disconnected";
                break;
        }
        cell.peerStateLabel.text = stateText;
        
    }
    
    return cell;
}


#pragma mark - Touch ACTIONS

- (IBAction)reverbChanged:(id)sender {
    [[MPIGameManager instance] changeReverb:((UISwitch*)sender).isOn];
}

- (IBAction)gainChanged:(id)sender {
    [[MPIGameManager instance] changeRecordingGain:((UISlider*)sender).value];
}

- (IBAction)limiterChanged:(id)sender {
    [[MPIGameManager instance] changeLimiter:((UISwitch*)sender).isOn];
}

- (IBAction)expanderChanged:(id)sender {
    [[MPIGameManager instance] changeExpander:((UISwitch*)sender).isOn];
}
@end
