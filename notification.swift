import Foundation
import AppKit
import UserNotifications

private let kReauthCategoryIdentifier = "REAUTH_CATEGORY"
private let kReauthActionIdentifier = "REAUTH_ACTION"
private let kTestCategoryIdentifier = "TEST_CATEGORY"
private let kTestActionIdentifier = "TEST_ACTION"
private let kRepoURL = "https://github.com/delphinus/homebrew-check-gcloud-adc"
private let kURLScheme = "check-gcloud-adc"

private func openWezTermForReauth() {
    let task = Process()
    task.launchPath = "/bin/bash"
    task.arguments = [
        "-c",
        "wezterm cli spawn -- bash -c 'gcloud auth login --update-adc; echo Done; read'"
    ]
    try? task.run()
}

private func registerNotificationCategories(_ center: UNUserNotificationCenter) {
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
}

class ActionHandler: NSObject, UNUserNotificationCenterDelegate {
    var actionHandled = false

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
                openWezTermForReauth()
            }
        }
        actionHandled = true
        completionHandler()
    }

    @objc func handleGetURL(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: urlString),
              url.scheme == kURLScheme else {
            return
        }

        switch url.host {
        case "reauth":
            openWezTermForReauth()
        case "open-repo":
            if let repoURL = URL(string: kRepoURL) {
                NSWorkspace.shared.open(repoURL)
            }
        default:
            break
        }
        actionHandled = true
    }
}

// Keep a strong reference to prevent deallocation during event loop
private var sharedHandler: ActionHandler?

@_cdecl("HandlePendingActions")
func handlePendingActions() -> Int32 {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)

    let handler = ActionHandler()
    sharedHandler = handler

    let center = UNUserNotificationCenter.current()
    center.delegate = handler
    registerNotificationCategories(center)

    // Register URL scheme handler
    NSAppleEventManager.shared().setEventHandler(
        handler,
        andSelector: #selector(ActionHandler.handleGetURL(_:withReplyEvent:)),
        forEventClass: AEEventClass(kInternetEventClass),
        andEventID: AEEventID(kAEGetURL)
    )

    // Process NSApplication events to receive Apple Events (URL scheme) and notification responses
    let timeout = Date(timeIntervalSinceNow: 1.0)
    while !handler.actionHandled && Date() < timeout {
        guard let event = NSApp.nextEvent(matching: .any, until: Date(timeIntervalSinceNow: 0.1), inMode: .default, dequeue: true) else {
            continue
        }
        NSApp.sendEvent(event)
    }
    return handler.actionHandled ? 1 : 0
}

@_cdecl("SendNotification")
func sendNotification(title: UnsafePointer<CChar>, message: UnsafePointer<CChar>, isTest: Int32) {
    let titleStr = String(cString: title)
    let messageStr = String(cString: message)

    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)

    let center = UNUserNotificationCenter.current()
    registerNotificationCategories(center)

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
}
