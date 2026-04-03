import Foundation

enum L10n {
    private static let isJapanese: Bool = {
        Locale.current.language.languageCode == .japanese
    }()

    // MARK: - Notification titles
    static var notificationTitleExpired: String {
        isJapanese ? "Google Cloud ADC 期限切れ" : "Google Cloud ADC Expired"
    }
    static var notificationTitleTest: String {
        isJapanese ? "テスト通知" : "Test Notification"
    }

    // MARK: - Notification messages
    static func notificationMessageAccountExpired(_ account: String) -> String {
        if isJapanese {
            return "\(account): gcloud auth login --update-adc で再認証してください"
        } else {
            return "\(account): Click to re-authenticate with gcloud auth login --update-adc"
        }
    }
    static var notificationMessageAdcExpired: String {
        isJapanese
            ? "Application Default Credentials の有効期限が切れました。クリックして再認証してください。"
            : "Application Default Credentials have expired. Click to re-authenticate."
    }
    static var notificationMessageTest: String {
        isJapanese ? "通知は正常に動作しています！" : "Notifications are working!"
    }

    // MARK: - Notification actions
    static var notificationActionReauth: String {
        isJapanese ? "再認証" : "Re-authenticate"
    }
    static var notificationActionOpenRepo: String {
        isJapanese ? "リポジトリを開く" : "Open Repository"
    }

    // MARK: - CLI output
    static var cliTestWaiting: String {
        isJapanese
            ? "通知を送信しました。クリックを待っています…（Ctrl+C でキャンセル）"
            : "Notification sent. Waiting for click... (Ctrl+C to cancel)"
    }
    static var cliTestHandled: String {
        isJapanese ? "通知アクションを処理しました。" : "Notification action handled."
    }
    static var cliTestTimeout: String {
        isJapanese
            ? "通知クリックの待機がタイムアウトしました。"
            : "Timed out waiting for notification click."
    }
    static var cliResetOpening: String {
        isJapanese
            ? "システム設定 > 通知を開いています…"
            : "Opening System Settings > Notifications..."
    }
    static var cliResetTip: String {
        isJapanese
            ? "ヒント: 通知スタイルを「通知」に設定すると、クリックするまで通知が表示され続けます。"
            : "Tip: Set the notification style to \"Alerts\" so notifications stay until clicked."
    }
}
