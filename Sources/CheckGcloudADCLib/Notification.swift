import Foundation
import AppKit
import UserNotifications

public final class NotificationSystem: Notifier, DeliveryChecker, ActionWaiter {
    private var handler: ActionHandler?
    private let center = UNUserNotificationCenter.current()

    public init() {}

    public func handlePendingActions() -> Bool {
        let handler = ensureSetup()
        runEventLoop(handler: handler, timeoutSeconds: 5.0)
        waitForReauth(handler: handler)
        return handler.actionHandled
    }

    public func send(title: String, message: String, isTest: Bool, identifier: String, account: String?) {
        _ = ensureSetup()

        let sema = DispatchSemaphore(value: 0)
        var authorized = false
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            authorized = granted
            if let error = error {
                fputs("notification authorization error: \(error.localizedDescription)\n", stderr)
            }
            sema.signal()
        }
        sema.wait()

        guard authorized else {
            fputs("notifications not authorized; enable in System Settings > Notifications\n", stderr)
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        content.sound = .default
        content.categoryIdentifier = isTest ? Identifier.testCategory : Identifier.reauthCategory
        if let account = account {
            content.userInfo = ["account": account]
        }

        let request = UNNotificationRequest(
            identifier: identifier,
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

    public func isDelivered(identifier: String) -> Bool {
        let sema = DispatchSemaphore(value: 0)
        var found = false
        center.getDeliveredNotifications { notifications in
            found = notifications.contains { $0.request.identifier == identifier }
            sema.signal()
        }
        sema.wait()
        return found
    }

    @discardableResult
    public func waitForAction(timeoutSeconds: Double) -> Bool {
        let handler = ensureSetup()
        runEventLoop(handler: handler, timeoutSeconds: timeoutSeconds)
        waitForReauth(handler: handler)
        return handler.actionHandled
    }
}

// MARK: - Privates

private extension NotificationSystem {
    func ensureSetup() -> ActionHandler {
        if let handler = self.handler { return handler }

        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)

        let handler = ActionHandler()
        self.handler = handler

        NSApp.delegate = handler

        NSAppleEventManager.shared().setEventHandler(
            handler,
            andSelector: #selector(ActionHandler.handleGetURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )

        NSApp.finishLaunching()

        center.delegate = handler
        registerNotificationCategories()

        return handler
    }

    func registerNotificationCategories() {
        let reauthAction = UNNotificationAction(
            identifier: Identifier.reauthAction,
            title: L10n.notificationActionReauth,
            options: []
        )
        let reauthCategory = UNNotificationCategory(
            identifier: Identifier.reauthCategory,
            actions: [reauthAction],
            intentIdentifiers: [],
            options: []
        )

        let testAction = UNNotificationAction(
            identifier: Identifier.testAction,
            title: L10n.notificationActionOpenRepo,
            options: []
        )
        let testCategory = UNNotificationCategory(
            identifier: Identifier.testCategory,
            actions: [testAction],
            intentIdentifiers: [],
            options: []
        )

        center.setNotificationCategories([reauthCategory, testCategory])
    }

    func runEventLoop(handler: ActionHandler, timeoutSeconds: Double) {
        let timeout = Date(timeIntervalSinceNow: timeoutSeconds)
        while !handler.actionHandled && Date() < timeout {
            if let event = NSApp.nextEvent(
                matching: .any,
                until: Date(timeIntervalSinceNow: 0.1),
                inMode: .default,
                dequeue: true
            ) {
                NSApp.sendEvent(event)
            }
        }
    }

    func waitForReauth(handler: ActionHandler) {
        if let proc = handler.reauthProcess, proc.isRunning {
            proc.waitUntilExit()
        }
    }
}
