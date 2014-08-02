//
//  MPISettingsViewController.m
//  Multipeer.Instrument
//
//  Created by Kyle Beyer on 8/2/14.
//  Copyright (c) 2014 Kyle Beyer. All rights reserved.
//

#import "MPISettingsViewController.h"
#import "MPIEventLogger.h"
#import "GameManager.h"

@interface MPISettingsViewController ()
{
    NSArray* _arrLogLevelOptions;
}
@end

@implementation MPISettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    // initialize log level options
    _arrLogLevelOptions = [[NSArray alloc] initWithObjects:
        @"Off",
        @"Debug",
        @"Info",
        @"Warn",
        @"Error",
        @"Fatal", nil];
    
    // set log level based on current
    [_logLevelPicker selectRow:[MPIEventLogger sharedInstance].logLevel inComponent:0 animated:NO];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
    
    
    // update log level
    [MPIEventLogger sharedInstance].logLevel = (MPILoggerLevel)[_logLevelPicker selectedRowInComponent:0];
}


#pragma mark - UIPickerView delgate
-(NSInteger)numberOfComponentsInPickerView:(UIPickerView *)pickerView
{
    return 1;
}
-(NSInteger)pickerView:(UIPickerView *)pickerView numberOfRowsInComponent:(NSInteger)component
{
    //set number of rows
    return _arrLogLevelOptions.count;
}
-(NSString *)pickerView:(UIPickerView *)pickerView titleForRow:(NSInteger)row forComponent:(NSInteger)component
{
    //set item per row
    return [_arrLogLevelOptions objectAtIndex:row];
}


#pragma mark - UI actions

- (IBAction)logToApi:(id)sender {
    UISwitch* apiSwitch = (UISwitch*)sender;
    if (apiSwitch.isOn) {
        [MPIEventLogger sharedInstance].logDestination = MPILogDestinationALL;
    } else {
        [MPIEventLogger sharedInstance].logDestination = MPILogDestinationConsole;
    }
}

- (IBAction)advertiseChanged:(id)sender {
    UISwitch* advertiseSwitch = (UISwitch*)sender;
    
    if (advertiseSwitch.isOn) {
        [[MPIGameManager instance].sessionController startAdvertising];
    } else {
        [[MPIGameManager instance].sessionController stopAdvertising];
    }
    
}

- (IBAction)browseChanged:(id)sender {
    UISwitch* advertiseSwitch = (UISwitch*)sender;
    
    if (advertiseSwitch.isOn) {
        [[MPIGameManager instance].sessionController startBrowsing];
    } else {
        [[MPIGameManager instance].sessionController stopBrowsing];
    }
}

- (IBAction)donePressed:(id)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
}



@end
