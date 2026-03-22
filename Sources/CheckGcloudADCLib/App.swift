import Foundation

// MARK: - Protocols

public protocol Notifier {
    func send(title: String, message: String, isTest: Bool, identifier: String, account: String?)
}

public protocol ADCChecker {
    func checkAll() -> [String]
}

public protocol DeliveryChecker {
    func isDelivered(identifier: String) -> Bool
}

public protocol ActionWaiter {
    @discardableResult
    func waitForAction(timeoutSeconds: Double) -> Bool
}

// MARK: - App

public final class App {
    private let notifier: any Notifier
    private let adcChecker: any ADCChecker
    private let deliveryChecker: any DeliveryChecker
    private let actionWaiter: any ActionWaiter

    public init(
        notifier: any Notifier,
        adcChecker: any ADCChecker,
        deliveryChecker: any DeliveryChecker,
        actionWaiter: any ActionWaiter
    ) {
        self.notifier = notifier
        self.adcChecker = adcChecker
        self.deliveryChecker = deliveryChecker
        self.actionWaiter = actionWaiter
    }

    public func test() {
        notifier.send(
            title: "Test Notification",
            message: "Notifications are working!",
            isTest: true,
            identifier: "check-gcloud-adc-test",
            account: nil
        )
        print("Notification sent. Waiting for click... (Ctrl+C to cancel)")
        if actionWaiter.waitForAction(timeoutSeconds: 120) {
            print("Notification action handled.")
        } else {
            print("Timed out waiting for notification click.")
        }
    }

    public func reset() {
        print("Opening System Settings > Notifications...")
        print("Tip: Set the notification style to \"Alerts\" so notifications stay until clicked.")
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["x-apple.systempreferences:com.apple.Notifications-Settings"]
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            fputs("failed to open System Settings: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    public func check() {
        let expiredAccounts = adcChecker.checkAll()
        guard !expiredAccounts.isEmpty else { return }

        var sent = false
        for account in expiredAccounts {
            let identifier = "check-gcloud-adc-\(account)"
            guard !deliveryChecker.isDelivered(identifier: identifier) else { continue }
            notifier.send(
                title: "Google Cloud ADC Expired",
                message: "\(account): Click to re-authenticate with gcloud auth login --update-adc",
                isTest: false,
                identifier: identifier,
                account: account
            )
            sent = true
        }

        if sent {
            actionWaiter.waitForAction(timeoutSeconds: 270)
        }
    }
}
