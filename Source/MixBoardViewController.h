//
//  MPIMixBoardViewController.h
//  Multipeer.Instrument
//
//  Created by Kyle Beyer on 6/10/14.
//  Copyright (c) 2014 Kyle Beyer. All rights reserved.
//

@import UIKit;
@import MediaPlayer;
@import AVFoundation;

@interface MPIMixBoardViewController : UITableViewController<UITableViewDataSource, UITableViewDelegate, AVAudioPlayerDelegate>

@property (strong, nonatomic) IBOutlet UITableView *participantTableView;
@property (weak, nonatomic) IBOutlet UILabel *nameLabel;
@property (weak, nonatomic) IBOutlet UILabel *timeLabel;
@property (weak, nonatomic) IBOutlet UILabel *timeWithOffsetLabel;
@property (weak, nonatomic) IBOutlet UILabel *localSessionStateLabel;
- (IBAction)reverbChanged:(id)sender;
- (IBAction)gainChanged:(id)sender;
- (IBAction)limiterChanged:(id)sender;
- (IBAction)expanderChanged:(id)sender;


@end