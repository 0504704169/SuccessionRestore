//
//  RestoreViewController.m
//  SuccessionRestore
//
//  Created by Sam Gardner on 6/30/18.
//  Copyright © 2018 Sam Gardner. All rights reserved.
//

#import "RestoreViewController.h"
#include <spawn.h>
#import "libjb.h"
#import "unjail.h"
#import "NSTask.h"

int attach(const char *path, char buf[], size_t sz);

@interface RestoreViewController ()

@end

@implementation RestoreViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [[UIApplication sharedApplication] setIdleTimerDisabled:TRUE];
    [[self outputLabel] setHidden:TRUE];
    [[self fileListActivityIndicator] setHidden:TRUE];
    [[self restoreProgressBar] setHidden:TRUE];
    [[self headerLabel] setText:@"Preparing..."];
    [[self infoLabel] setText:@"Attaching rootfilesystem"];
    [_startRestoreButton setEnabled:FALSE];
    NSArray *origDevContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:@"/dev/" error:nil];
    [self->_startRestoreButton setUserInteractionEnabled:FALSE];
    [_startRestoreButton setTitleColor:[UIColor darkGrayColor] forState:UIControlStateNormal];
    [[NSFileManager defaultManager] createDirectoryAtPath:@"/private/var/MobileSoftwareUpdate/mnt1/" withIntermediateDirectories:TRUE attributes:nil error:nil];
    char thedisk[11];
    NSString *bootstrap = @"/var/mobile/Media/Succession/rfs.dmg";
    if (kCFCoreFoundationVersionNumber < 1349.56) {
        _filesystemType = @"hfs";
    } else if (kCFCoreFoundationVersionNumber > 1349.56){
        _filesystemType = @"apfs";
    }
    int rv = attach([bootstrap UTF8String], thedisk, sizeof(thedisk));
    NSMutableArray *changedDevContents = [NSMutableArray arrayWithArray:[[NSFileManager defaultManager] contentsOfDirectoryAtPath:@"/dev/" error:nil]];
    [changedDevContents removeObjectsInArray:origDevContents];
    NSString *attachedDMGDiskName = [[NSString alloc] init];
    for (NSString * object in origDevContents) {
        if ([object containsString:@"s2"] && ![object containsString:@"rdisk"]) {
            attachedDMGDiskName = [NSString stringWithFormat:@"/dev/%@", object];
        }
    }
    if (attachedDMGDiskName == nil) {
        [self errorAlert:@"Unable to find attached DMG"];
    }
    NSArray *mountArgs = [NSArray arrayWithObjects:@"-t", _filesystemType, @"-o", @"ro", attachedDMGDiskName, @"/var/MobileSoftwareUpdate/mnt1", nil];
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        [[self infoLabel] setText:@"Mounting DMG, please wait..."];
        if (rv == 0) {
            NSTask *task = [[NSTask alloc] init];
            task.launchPath = @"/sbin/mount";
            task.arguments = mountArgs;
            task.terminationHandler = ^(NSTask *task){
                [[self headerLabel] setText:@"WARNING!"];
                [[self infoLabel] setText:@"Running this tool will immediately delete all data from your device. Please make a backup of any data that you want to keep. This will also return your device to the setup screen.  A valid SIM card may be needed for activation on iPhones."];
                [self->_startRestoreButton setEnabled:TRUE];
                [self->_startRestoreButton setUserInteractionEnabled:TRUE];
                [self->_startRestoreButton setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
            };
            [task launch];
        } else {
            [self errorAlert:@"Failed to attach DMG"];
        }
    });
    
}

- (IBAction)startRestoreButtonAction:(id)sender {
    UIAlertController *areYouSureAlert = [UIAlertController alertControllerWithTitle:@"Are you sure you would like to begin restoring" message:@"You will not be able to leave the app during the process" preferredStyle:UIAlertControllerStyleActionSheet];
    UIAlertAction *beginRestore = [UIAlertAction actionWithTitle:@"Begin restore" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        [self successionRestore];
    }];
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil];
    [areYouSureAlert addAction:beginRestore];
    [areYouSureAlert addAction:cancelAction];
    [self presentViewController:areYouSureAlert animated:TRUE completion:nil];
}

- (void)prepareForRestore {
    [[self headerLabel] setText:@"Restoring, do not leave the app..."];
}

-(void)successionRestore{
    if ([[NSFileManager defaultManager] fileExistsAtPath:@"/private/var/MobileSoftwareUpdate/mnt1/sbin/launchd"]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:@"/private/var/mobile/Media/Succession/testing/" withIntermediateDirectories:TRUE attributes:nil error:nil];
        NSArray *rsyncArgs = [NSArray arrayWithObjects:@"-vaxcH", @"--delete-after", @"--progress", @"--exclude=/Developer", @"--exclude=/System/Library/Caches/apticket.der", @"--exclude=/usr/local/standalone/firmware/Baseband", @"/var/MobileSoftwareUpdate/mnt1/.", @"/var/mobile/Media/Succession/testing", nil];
        NSTask *rsyncTask = [[NSTask alloc] init];
        [rsyncTask setLaunchPath:@"/usr/bin/rsync"];
        [rsyncTask setArguments:rsyncArgs];
        NSPipe *outputPipe = [NSPipe pipe];
        [rsyncTask setStandardOutput:outputPipe];
        NSFileHandle *stdoutHandle = [outputPipe fileHandleForReading];
        [stdoutHandle waitForDataInBackgroundAndNotify];
        id observer = [[NSNotificationCenter defaultCenter] addObserverForName:NSFileHandleDataAvailableNotification
                                                                        object:stdoutHandle queue:nil
                                                                    usingBlock:^(NSNotification *note)
        {
            
            NSData *dataRead = [stdoutHandle availableData];
            NSString *stringRead = [[NSString alloc] initWithData:dataRead encoding:NSUTF8StringEncoding];
            if ([stringRead containsString:@"00 files..."]) {
                [[self infoLabel] setText:@"Bulding file list, please wait..."];
                [[self fileListActivityIndicator] setHidden:FALSE];
                [[self restoreProgressBar] setHidden:TRUE];
            }
            if ([stringRead hasPrefix:@"Applications/"]) {
                [[self infoLabel] setText:@"Rebuilding Applications..."];
                [[self fileListActivityIndicator] setHidden:TRUE];
                [[self restoreProgressBar] setHidden:FALSE];
                [[self restoreProgressBar] setProgress:0];
            }
            if ([stringRead hasPrefix:@"Library/"]) {
                [[self infoLabel] setText:@"Rebuliding Library..."];
                [[self fileListActivityIndicator] setHidden:TRUE];
                [[self restoreProgressBar] setHidden:FALSE];
                [[self restoreProgressBar] setProgress:0.33];
            }
            if ([stringRead hasPrefix:@"System/"]) {
                [[self infoLabel] setText:@"Rebuliding System..."];
                [[self fileListActivityIndicator] setHidden:TRUE];
                [[self restoreProgressBar] setHidden:FALSE];
                [[self restoreProgressBar] setProgress:0.67];
            }
            if ([stringRead hasPrefix:@"usr/"]) {
                [[self infoLabel] setText:@"Rebuliding usr..."];
                [[self fileListActivityIndicator] setHidden:TRUE];
                [[self restoreProgressBar] setHidden:FALSE];
                [[self restoreProgressBar] setProgress:0.9];
            }
            if ([stringRead containsString:@"speedup is"]) {
                [[self headerLabel] setText:@"Restore complete"];
                [[self fileListActivityIndicator] setHidden:TRUE];
                [[self restoreProgressBar] setHidden:FALSE];
                [[self restoreProgressBar] setProgress:1.0];
                 [[NSNotificationCenter defaultCenter] removeObserver:observer];
            }
            [[self outputLabel] setText:stringRead];
            [stdoutHandle waitForDataInBackgroundAndNotify];
        }];
        [[self headerLabel] setText:@"Working, do not leave the app..."];
        [[self fileListActivityIndicator] setHidden:FALSE];
        [rsyncTask launch];
    } else {
        [self errorAlert:@"Mountpoint does not contain rootfilesystem, please restart the app and try again."];
    }

}


-(void)errorAlert:(NSString *)message{
    UIAlertController *errorAlertController = [UIAlertController alertControllerWithTitle:@"Error" message:message preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *exitAction = [UIAlertAction actionWithTitle:@"exit" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        exit(0);
    }];
    [errorAlertController addAction:exitAction];
    [self presentViewController:errorAlertController animated:TRUE completion:nil];
}
@end
