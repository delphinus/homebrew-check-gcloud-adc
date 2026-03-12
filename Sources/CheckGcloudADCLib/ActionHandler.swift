import AppKit
import UserNotifications
import Foundation

final class ActionHandler: NSObject {
    var actionHandled = false
    var reauthProcess: Process?

    @objc func handleGetURL(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: urlString),
              url.scheme == AppURL.scheme else {
            return
        }
        switch url.host {
        case "reauth":
            reauthProcess = GcloudReauth.run()
        case "open-repo":
            if let repoURL = AppURL.repo {
                NSWorkspace.shared.open(repoURL)
            }
        default:
            break
        }
        actionHandled = true
    }
}

// MARK: - NSApplicationDelegate

extension ActionHandler: NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard url.scheme == AppURL.scheme else { continue }
            switch url.host {
            case "reauth":
                reauthProcess = GcloudReauth.run()
            case "open-repo":
                if let repoURL = AppURL.repo {
                    NSWorkspace.shared.open(repoURL)
                }
            default:
                break
            }
            actionHandled = true
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension ActionHandler: UNUserNotificationCenterDelegate {
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

        if categoryId == Identifier.testCategory {
            if let url = AppURL.repo {
                NSWorkspace.shared.open(url)
            }
        } else if categoryId == Identifier.reauthCategory {
            if response.actionIdentifier == Identifier.reauthAction ||
               response.actionIdentifier == UNNotificationDefaultActionIdentifier {
                reauthProcess = GcloudReauth.run()
            }
        }
        actionHandled = true
        completionHandler()
    }
}
