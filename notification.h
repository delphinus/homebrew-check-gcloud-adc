#ifndef NOTIFICATION_H
#define NOTIFICATION_H

void SendNotification(const char *title, const char *message, int isTest);
int IsNotificationDelivered(void);
int HandlePendingActions(void);
int WaitForNotificationAction(double timeoutSeconds);

#endif
