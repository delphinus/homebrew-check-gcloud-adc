#import <Foundation/Foundation.h>
#import <UserNotifications/UserNotifications.h>

#include "notification.h"

static NSString *const kCategoryIdentifier = @"REAUTH_CATEGORY";
static NSString *const kActionIdentifier = @"REAUTH_ACTION";

@interface NotificationDelegate : NSObject <UNUserNotificationCenterDelegate>
@property (nonatomic, assign) BOOL wasClicked;
@end

@implementation NotificationDelegate

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
       willPresentNotification:(UNNotification *)notification
         withCompletionHandler:(void (^)(UNNotificationPresentationOptions))completionHandler {
    completionHandler(UNNotificationPresentationOptionBanner |
                      UNNotificationPresentationOptionSound);
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
didReceiveNotificationResponse:(UNNotificationResponse *)response
         withCompletionHandler:(void (^)(void))completionHandler {
    if ([response.actionIdentifier isEqualToString:kActionIdentifier] ||
        [response.actionIdentifier isEqualToString:UNNotificationDefaultActionIdentifier]) {
        NSTask *task = [[NSTask alloc] init];
        task.launchPath = @"/bin/bash";
        task.arguments = @[
            @"-c",
            @"wezterm cli spawn -- bash -c 'gcloud auth login --update-adc; echo Done; read'"
        ];
        [task launch];
    }
    self.wasClicked = YES;
    completionHandler();
}

@end

void SendNotification(const char *title, const char *message) {
    @autoreleasepool {
        NotificationDelegate *delegate = [[NotificationDelegate alloc] init];
        UNUserNotificationCenter *center =
            [UNUserNotificationCenter currentNotificationCenter];
        center.delegate = delegate;

        // Register category with Re-authenticate action
        UNNotificationAction *action =
            [UNNotificationAction actionWithIdentifier:kActionIdentifier
                                                 title:@"Re-authenticate"
                                               options:UNNotificationActionOptionForeground];
        UNNotificationCategory *category =
            [UNNotificationCategory categoryWithIdentifier:kCategoryIdentifier
                                                   actions:@[action]
                                         intentIdentifiers:@[]
                                                   options:0];
        [center setNotificationCategories:[NSSet setWithObject:category]];

        // Request authorization
        dispatch_semaphore_t authSema = dispatch_semaphore_create(0);
        __block BOOL authorized = NO;
        [center requestAuthorizationWithOptions:(UNAuthorizationOptionAlert |
                                                 UNAuthorizationOptionSound)
                              completionHandler:^(BOOL granted, NSError *error) {
            authorized = granted;
            if (error) {
                fprintf(stderr, "notification authorization error: %s\n",
                        [[error localizedDescription] UTF8String]);
            }
            dispatch_semaphore_signal(authSema);
        }];
        dispatch_semaphore_wait(authSema, DISPATCH_TIME_FOREVER);

        if (!authorized) {
            fprintf(stderr, "notifications not authorized; enable in System Settings > Notifications\n");
            return;
        }

        // Build and deliver notification
        UNMutableNotificationContent *content =
            [[UNMutableNotificationContent alloc] init];
        content.title = [NSString stringWithUTF8String:title];
        content.body = [NSString stringWithUTF8String:message];
        content.sound = [UNNotificationSound defaultSound];
        content.categoryIdentifier = kCategoryIdentifier;

        UNNotificationRequest *request =
            [UNNotificationRequest requestWithIdentifier:@"check-gcloud-adc"
                                                 content:content
                                                 trigger:nil];

        dispatch_semaphore_t deliverSema = dispatch_semaphore_create(0);
        [center addNotificationRequest:request
                 withCompletionHandler:^(NSError *error) {
            if (error) {
                fprintf(stderr, "notification delivery error: %s\n",
                        [[error localizedDescription] UTF8String]);
            }
            dispatch_semaphore_signal(deliverSema);
        }];
        dispatch_semaphore_wait(deliverSema, DISPATCH_TIME_FOREVER);

        // Run the run loop briefly to allow click handling
        NSDate *timeout = [NSDate dateWithTimeIntervalSinceNow:30.0];
        while (!delegate.wasClicked &&
               [[NSDate date] compare:timeout] == NSOrderedAscending) {
            [[NSRunLoop currentRunLoop]
                runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];
        }
    }
}
