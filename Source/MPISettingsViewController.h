//
//  MPISettingsViewController.h
//  Multipeer.Instrument
//
//  Created by Kyle Beyer on 8/2/14.
//  Copyright (c) 2014 Kyle Beyer. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface MPISettingsViewController : UIViewController<UIPickerViewDataSource, UIPickerViewDelegate>

@property (weak, nonatomic) IBOutlet UIPickerView *logLevelPicker;

- (IBAction)logToApi:(id)sender;
- (IBAction)advertiseChanged:(id)sender;
- (IBAction)browseChanged:(id)sender;

- (IBAction)donePressed:(id)sender;
- (IBAction)resetPeerID:(id)sender;
@end
