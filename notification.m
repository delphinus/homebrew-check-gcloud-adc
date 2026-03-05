#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

#include "notification.h"

// Delegate to handle notification click
@interface NotificationDelegate : NSObject <NSUserNotificationCenterDelegate>
@property (nonatomic, assign) BOOL wasClicked;
@end

@implementation NotificationDelegate

- (BOOL)userNotificationCenter:(NSUserNotificationCenter *)center
     shouldPresentNotification:(NSUserNotification *)notification {
    return YES;
}

- (void)userNotificationCenter:(NSUserNotificationCenter *)center
       didActivateNotification:(NSUserNotification *)notification {
    self.wasClicked = YES;

    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/bin/bash";
    task.arguments = @[
        @"-c",
        @"wezterm cli spawn -- bash -c 'gcloud auth login --update-adc; echo Done; read'"
    ];
    [task launch];

    [center removeDeliveredNotification:notification];
}

@end

void SendNotification(const char *title, const char *message) {
    @autoreleasepool {
        NotificationDelegate *delegate = [[NotificationDelegate alloc] init];

        NSUserNotificationCenter *center =
            [NSUserNotificationCenter defaultUserNotificationCenter];
        center.delegate = delegate;

        NSUserNotification *notification = [[NSUserNotification alloc] init];
        notification.title = [NSString stringWithUTF8String:title];
        notification.informativeText = [NSString stringWithUTF8String:message];
        notification.soundName = NSUserNotificationDefaultSoundName;

        [center deliverNotification:notification];

        // Run the run loop briefly to allow click handling
        NSDate *timeout = [NSDate dateWithTimeIntervalSinceNow:30.0];
        while (!delegate.wasClicked &&
               [[NSDate date] compare:timeout] == NSOrderedAscending) {
            [[NSRunLoop currentRunLoop]
                runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];
        }
    }
}
