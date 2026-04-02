import Foundation

enum L10n {
    // MARK: - Notification titles
    static var notificationTitleExpired: String {
        NSLocalizedString("notification.title.expired", bundle: .module, comment: "")
    }
    static var notificationTitleTest: String {
        NSLocalizedString("notification.title.test", bundle: .module, comment: "")
    }

    // MARK: - Notification messages
    static func notificationMessageAccountExpired(_ account: String) -> String {
        String(format: NSLocalizedString("notification.message.account_expired", bundle: .module, comment: ""), account)
    }
    static var notificationMessageAdcExpired: String {
        NSLocalizedString("notification.message.adc_expired", bundle: .module, comment: "")
    }
    static var notificationMessageTest: String {
        NSLocalizedString("notification.message.test", bundle: .module, comment: "")
    }

    // MARK: - Notification actions
    static var notificationActionReauth: String {
        NSLocalizedString("notification.action.reauth", bundle: .module, comment: "")
    }
    static var notificationActionOpenRepo: String {
        NSLocalizedString("notification.action.open_repo", bundle: .module, comment: "")
    }

    // MARK: - CLI output
    static var cliTestWaiting: String {
        NSLocalizedString("cli.test.waiting", bundle: .module, comment: "")
    }
    static var cliTestHandled: String {
        NSLocalizedString("cli.test.handled", bundle: .module, comment: "")
    }
    static var cliTestTimeout: String {
        NSLocalizedString("cli.test.timeout", bundle: .module, comment: "")
    }
    static var cliResetOpening: String {
        NSLocalizedString("cli.reset.opening", bundle: .module, comment: "")
    }
    static var cliResetTip: String {
        NSLocalizedString("cli.reset.tip", bundle: .module, comment: "")
    }
}
