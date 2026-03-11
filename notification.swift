import Foundation
import AppKit
import UserNotifications

private let kReauthCategoryIdentifier = "REAUTH_CATEGORY"
private let kReauthActionIdentifier = "REAUTH_ACTION"
private let kTestCategoryIdentifier = "TEST_CATEGORY"
private let kTestActionIdentifier = "TEST_ACTION"
private let kRepoURL = "https://github.com/delphinus/homebrew-check-gcloud-adc"
private let kURLScheme = "check-gcloud-adc"

private var reauthProcess: Process?

private func runReauth() {
    let task = Process()
    task.launchPath = "/bin/zsh"
    task.arguments = ["-l", "-c", "gcloud auth login --update-adc"]
    try? task.run()
    reauthProcess = task
}

private func registerNotificationCategories(_ center: UNUserNotificationCenter) {
    let reauthAction = UNNotificationAction(
        identifier: kReauthActionIdentifier,
        title: "Re-authenticate",
        options: []
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
        options: []
    )
    let testCategory = UNNotificationCategory(
        identifier: kTestCategoryIdentifier,
        actions: [testAction],
        intentIdentifiers: [],
        options: []
    )

    center.setNotificationCategories([reauthCategory, testCategory])
}

class ActionHandler: NSObject, UNUserNotificationCenterDelegate, NSApplicationDelegate {
    var actionHandled = false

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard url.scheme == kURLScheme else { continue }
            switch url.host {
            case "reauth":
                runReauth()
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
                runReauth()
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
            runReauth()
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

private func runEventLoop(handler: ActionHandler, timeoutSeconds: Double) {
    let timeout = Date(timeIntervalSinceNow: timeoutSeconds)
    while !handler.actionHandled && Date() < timeout {
        if let event = NSApp.nextEvent(matching: .any, until: Date(timeIntervalSinceNow: 0.1), inMode: .default, dequeue: true) {
            NSApp.sendEvent(event)
        }
    }
}

private func setupActionHandler() -> ActionHandler {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    setAppIcon()

    let handler = ActionHandler()
    sharedHandler = handler

    // Set as app delegate to receive application:open:urls:
    NSApp.delegate = handler

    // Register URL scheme handler before finishLaunching so queued events are caught
    NSAppleEventManager.shared().setEventHandler(
        handler,
        andSelector: #selector(ActionHandler.handleGetURL(_:withReplyEvent:)),
        forEventClass: AEEventClass(kInternetEventClass),
        andEventID: AEEventID(kAEGetURL)
    )

    // finishLaunching delivers any queued Apple Events (e.g. URL scheme)
    NSApp.finishLaunching()

    let center = UNUserNotificationCenter.current()
    center.delegate = handler
    registerNotificationCategories(center)

    return handler
}

@_cdecl("HandlePendingActions")
func handlePendingActions() -> Int32 {
    let handler = setupActionHandler()
    runEventLoop(handler: handler, timeoutSeconds: 5.0)
    if let proc = reauthProcess, proc.isRunning {
        proc.waitUntilExit()
    }
    return handler.actionHandled ? 1 : 0
}

@_cdecl("WaitForNotificationAction")
func waitForNotificationAction(timeoutSeconds: Double) -> Int32 {
    let handler = setupActionHandler()
    runEventLoop(handler: handler, timeoutSeconds: timeoutSeconds)
    if let proc = reauthProcess, proc.isRunning {
        proc.waitUntilExit()
    }
    return handler.actionHandled ? 1 : 0
}

private func generateIconImage() -> NSImage {
    let s: CGFloat = 256
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()

    if let ctx = NSGraphicsContext.current?.cgContext {
        // Rounded rect with blue gradient background
        let radius = s * 0.2
        let bgPath = CGPath(roundedRect: CGRect(x: 0, y: 0, width: s, height: s),
                            cornerWidth: radius, cornerHeight: radius, transform: nil)
        ctx.addPath(bgPath)
        ctx.clip()

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let colors = [
            CGColor(red: 0.25, green: 0.55, blue: 0.95, alpha: 1.0),
            CGColor(red: 0.15, green: 0.35, blue: 0.75, alpha: 1.0),
        ] as CFArray
        let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0])!
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: 0), options: [])

        // Helper to draw tinted SF Symbol
        func drawTintedSymbol(_ name: String, pointSize: CGFloat, color: NSColor, in rect: NSRect) {
            guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return }
            let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .bold)
            guard let configured = symbol.withSymbolConfiguration(config) else { return }
            let tinted = NSImage(size: configured.size)
            tinted.lockFocus()
            color.set()
            let tintRect = NSRect(origin: .zero, size: configured.size)
            configured.draw(in: tintRect)
            tintRect.fill(using: .sourceAtop)
            tinted.unlockFocus()
            tinted.draw(in: rect)
        }

        // Cloud
        if let cloudSymbol = NSImage(systemSymbolName: "cloud.fill", accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: s * 0.45, weight: .bold)
            if let configured = cloudSymbol.withSymbolConfiguration(config) {
                let sz = configured.size
                let x = (s - sz.width) / 2
                let y = (s - sz.height) / 2 + s * 0.08
                drawTintedSymbol("cloud.fill", pointSize: s * 0.45,
                                 color: NSColor.white.withAlphaComponent(0.95),
                                 in: NSRect(x: x, y: y, width: sz.width, height: sz.height))
            }
        }

        // Key
        if let keySymbol = NSImage(systemSymbolName: "key.fill", accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: s * 0.22, weight: .bold)
            if let configured = keySymbol.withSymbolConfiguration(config) {
                let sz = configured.size
                let x = (s - sz.width) / 2 + s * 0.12
                let y = (s - sz.height) / 2 - s * 0.12
                let circleSize = max(sz.width, sz.height) * 1.4
                let cx = x + (sz.width - circleSize) / 2
                let cy = y + (sz.height - circleSize) / 2
                NSColor(red: 0.1, green: 0.25, blue: 0.6, alpha: 0.7).setFill()
                NSBezierPath(ovalIn: NSRect(x: cx, y: cy, width: circleSize, height: circleSize)).fill()
                drawTintedSymbol("key.fill", pointSize: s * 0.22,
                                 color: NSColor(red: 1.0, green: 0.85, blue: 0.3, alpha: 1.0),
                                 in: NSRect(x: x, y: y, width: sz.width, height: sz.height))
            }
        }
    }

    image.unlockFocus()
    return image
}

private func setAppIcon() {
    NSApp.applicationIconImage = generateIconImage()
}

@_cdecl("IsNotificationDelivered")
func isNotificationDelivered() -> Int32 {
    let center = UNUserNotificationCenter.current()
    let sema = DispatchSemaphore(value: 0)
    var found = false
    center.getDeliveredNotifications { notifications in
        found = notifications.contains { $0.request.identifier == "check-gcloud-adc" }
        sema.signal()
    }
    sema.wait()
    return found ? 1 : 0
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
