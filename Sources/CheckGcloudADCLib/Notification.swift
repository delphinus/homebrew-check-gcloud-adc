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
        NSApp.applicationIconImage = generateIconImage()

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
            title: "Re-authenticate",
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
            title: "Open Repository",
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

    private func generateIconImage() -> NSImage {
        let s: CGFloat = 256
        let image = NSImage(size: NSSize(width: s, height: s))
        image.lockFocus()

        if let ctx = NSGraphicsContext.current?.cgContext {
            let radius = s * 0.2
            let bgPath = CGPath(
                roundedRect: CGRect(x: 0, y: 0, width: s, height: s),
                cornerWidth: radius,
                cornerHeight: radius,
                transform: nil
            )
            ctx.addPath(bgPath)
            ctx.clip()

            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let colors = [
                CGColor(red: 0.25, green: 0.55, blue: 0.95, alpha: 1.0),
                CGColor(red: 0.15, green: 0.35, blue: 0.75, alpha: 1.0),
            ] as CFArray
            let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0])!
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: 0), options: [])

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

            if let cloudSymbol = NSImage(systemSymbolName: "cloud.fill", accessibilityDescription: nil) {
                let config = NSImage.SymbolConfiguration(pointSize: s * 0.45, weight: .bold)
                if let configured = cloudSymbol.withSymbolConfiguration(config) {
                    let sz = configured.size
                    let x = (s - sz.width) / 2
                    let y = (s - sz.height) / 2 + s * 0.08
                    drawTintedSymbol(
                        "cloud.fill",
                        pointSize: s * 0.45,
                        color: NSColor.white.withAlphaComponent(0.95),
                        in: NSRect(x: x, y: y, width: sz.width, height: sz.height)
                    )
                }
            }

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
                    drawTintedSymbol(
                        "key.fill",
                        pointSize: s * 0.22,
                        color: NSColor(red: 1.0, green: 0.85, blue: 0.3, alpha: 1.0),
                        in: NSRect(x: x, y: y, width: sz.width, height: sz.height)
                    )
                }
            }
        }

        image.unlockFocus()
        return image
    }
}
