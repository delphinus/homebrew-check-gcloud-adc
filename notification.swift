import Foundation
import AppKit
import UserNotifications

private let kReauthCategoryIdentifier = "REAUTH_CATEGORY"
private let kReauthActionIdentifier = "REAUTH_ACTION"
private let kTestCategoryIdentifier = "TEST_CATEGORY"
private let kTestActionIdentifier = "TEST_ACTION"
private let kRepoURL = "https://github.com/delphinus/homebrew-check-gcloud-adc"

class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    var wasClicked = false

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let categoryId = response.notification.request.content.categoryIdentifier

        if categoryId == kTestCategoryIdentifier {
            if let url = URL(string: kRepoURL) {
                NSWorkspace.shared.open(url)
            }
        } else if categoryId == kReauthCategoryIdentifier {
            if response.actionIdentifier == kReauthActionIdentifier ||
               response.actionIdentifier == UNNotificationDefaultActionIdentifier {
                let task = Process()
                task.launchPath = "/bin/bash"
                task.arguments = [
                    "-c",
                    "wezterm cli spawn -- bash -c 'gcloud auth login --update-adc; echo Done; read'"
                ]
                try? task.run()
            }
        }
        wasClicked = true
        completionHandler()
    }
}

@_cdecl("SendNotification")
func sendNotification(title: UnsafePointer<CChar>, message: UnsafePointer<CChar>, isTest: Int32) {
    let titleStr = String(cString: title)
    let messageStr = String(cString: message)

    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)

    let delegate = NotificationDelegate()
    let center = UNUserNotificationCenter.current()
    center.delegate = delegate

    // Register categories
    let reauthAction = UNNotificationAction(
        identifier: kReauthActionIdentifier,
        title: "Re-authenticate",
        options: .foreground
    )
    let reauthCategory = UNNotificationCategory(
        identifier: kReauthCategoryIdentifier,
        actions: [reauthAction],
        intentIdentifiers: [],
        options: []
    )

    let testAction = UNNotificationAction(
        identifier: kTestActionIdentifier,
        title: "Open Repository",
        options: .foreground
    )
    let testCategory = UNNotificationCategory(
        identifier: kTestCategoryIdentifier,
        actions: [testAction],
        intentIdentifiers: [],
        options: []
    )

    center.setNotificationCategories([reauthCategory, testCategory])

    // Request authorization
    let authSema = DispatchSemaphore(value: 0)
    var authorized = false
    center.requestAuthorization(options: [.alert, .sound]) { granted, error in
        authorized = granted
        if let error = error {
            fputs("notification authorization error: \(error.localizedDescription)\n", stderr)
        }
        authSema.signal()
    }
    authSema.wait()

    if !authorized {
        fputs("notifications not authorized; enable in System Settings > Notifications\n", stderr)
        return
    }

    // Build and deliver notification
    let content = UNMutableNotificationContent()
    content.title = titleStr
    content.body = messageStr
    content.sound = .default
    content.categoryIdentifier = isTest != 0 ? kTestCategoryIdentifier : kReauthCategoryIdentifier

    let request = UNNotificationRequest(
        identifier: "check-gcloud-adc",
        content: content,
        trigger: nil
    )

    let deliverSema = DispatchSemaphore(value: 0)
    center.add(request) { error in
        if let error = error {
            fputs("notification delivery error: \(error.localizedDescription)\n", stderr)
        }
        deliverSema.signal()
    }
    deliverSema.wait()

    // Run the run loop briefly to allow click handling
    let timeout = Date(timeIntervalSinceNow: 30.0)
    while !delegate.wasClicked && Date() < timeout {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.5))
    }
}
