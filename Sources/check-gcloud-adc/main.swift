import CheckGcloudADCLib
import Foundation

let notificationSystem = NotificationSystem()

guard !notificationSystem.handlePendingActions() else {
    exit(0)
}

let args = CommandLine.arguments

if args.contains("--help") || args.contains("-h") {
    print("check-gcloud-adc: Check Google Cloud ADC token validity")
    print()
    print("If the ADC token is expired or invalid, a macOS notification is sent.")
    print("Clicking the notification runs gcloud auth login --update-adc to re-authenticate.")
    print()
    print("You can also trigger actions via URL scheme:")
    print("  open check-gcloud-adc://reauth      re-authenticate")
    print("  open check-gcloud-adc://open-repo    open the repository")
    print()
    print("Flags:")
    print("  --help   show this help message")
    print("  --test   send a test notification (skips ADC check)")
    print("  --reset  open notification settings")
    exit(0)
}

let app = App(
    notifier: notificationSystem,
    adcChecker: GcloudADCChecker(),
    deliveryChecker: notificationSystem,
    actionWaiter: notificationSystem
)

if args.contains("--reset") {
    app.reset()
} else if args.contains("--test") {
    app.test()
} else {
    app.runCheck()
}
