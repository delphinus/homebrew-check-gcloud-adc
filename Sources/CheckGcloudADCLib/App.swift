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
            title: L10n.notificationTitleTest,
            message: L10n.notificationMessageTest,
            isTest: true,
            identifier: "check-gcloud-adc-test",
            account: nil
        )
        print(L10n.cliTestWaiting)
        if actionWaiter.waitForAction(timeoutSeconds: 120) {
            print(L10n.cliTestHandled)
        } else {
            print(L10n.cliTestTimeout)
        }
    }

    public func reset() {
        print(L10n.cliResetOpening)
        print(L10n.cliResetTip)
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
            let isADC = account == "application-default"
            notifier.send(
                title: L10n.notificationTitleExpired,
                message: isADC
                    ? L10n.notificationMessageAdcExpired
                    : L10n.notificationMessageAccountExpired(account),
                isTest: false,
                identifier: identifier,
                account: isADC ? nil : account
            )
            sent = true
        }

        if sent {
            actionWaiter.waitForAction(timeoutSeconds: 270)
        }
    }
}
