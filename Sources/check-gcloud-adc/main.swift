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
    print("By default every account from `gcloud auth list` is checked. Set")
    print("CHECK_GCLOUD_ADC_ACCOUNTS (comma/space separated) or write one account")
    print("per line to ~/.config/check-gcloud-adc/accounts to check only those.")
    print()
    print("Re-authentication happens in a dedicated Chrome window with a fixed")
    print("profile, and the window is closed once gcloud exits. The store page for")
    print("any missing extension (1Password by default) is opened alongside, so a")
    print("password manager stays available. Set CHECK_GCLOUD_ADC_BROWSER to another")
    print("Chromium-based executable, or to an empty string to fall back to the")
    print("default browser. CHECK_GCLOUD_ADC_BROWSER_PROFILE overrides where the")
    print("profile lives, CHECK_GCLOUD_ADC_BROWSER_EXTENSIONS which extensions to")
    print("prompt for (empty string to prompt for none), and")
    print("CHECK_GCLOUD_ADC_BROWSER_WINDOW the window size as WxH, centered on the")
    print("screen the mouse is on (empty string to leave it to Chrome).")
    print()
    print("Closing the dedicated window ends the re-authentication, and any run")
    print("still in flight is terminated before a new one starts, so triggering it")
    print("again always starts from a clean slate.")
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
    app.check()
}
