import CheckGcloudADCLib
import Foundation

struct NotifyCall {
    let title: String
    let message: String
    let isTest: Bool
    let identifier: String
    let account: String?
}

final class MockNotifier: Notifier {
    var calls: [NotifyCall] = []

    func send(title: String, message: String, isTest: Bool, identifier: String, account: String?) {
        calls.append(NotifyCall(title: title, message: message, isTest: isTest, identifier: identifier, account: account))
    }
}

final class MockADCChecker: ADCChecker {
    var expiredAccounts: [String] = []

    func checkAll() -> [String] { expiredAccounts }
}

final class MockDeliveryChecker: DeliveryChecker {
    var deliveredIdentifiers: Set<String> = []

    func isDelivered(identifier: String) -> Bool {
        deliveredIdentifiers.contains(identifier)
    }
}

final class MockActionWaiter: ActionWaiter {
    func waitForAction(timeoutSeconds: Double) -> Bool { false }
}

func makeTestApp() -> (App, MockNotifier, MockADCChecker, MockDeliveryChecker) {
    let n = MockNotifier()
    let c = MockADCChecker()
    let d = MockDeliveryChecker()
    let w = MockActionWaiter()
    let app = App(notifier: n, adcChecker: c, deliveryChecker: d, actionWaiter: w)
    return (app, n, c, d)
}

var passed = 0
var failed = 0

func assert(_ condition: Bool, _ message: String, file: String = #file, line: Int = #line) {
    if !condition {
        fputs("FAIL: \(message) (\(file):\(line))\n", stderr)
        failed += 1
    }
}

func test(_ name: String, _ body: () -> Void) {
    body()
    passed += 1
    print("  PASS: \(name)")
}

print("Running tests...")

test("check: all accounts valid -> no notification") {
    let (app, n, _, _) = makeTestApp()

    app.check()

    assert(n.calls.isEmpty, "expected no notification")
}

test("check: one account expired, not delivered -> sends notification") {
    let (app, n, c, d) = makeTestApp()
    c.expiredAccounts = ["user@example.com"]
    d.deliveredIdentifiers = []

    app.check()

    assert(n.calls.count == 1, "expected 1 notification, got \(n.calls.count)")
    assert(n.calls[0].title == "Google Cloud ADC Expired" || n.calls[0].title == "Google Cloud ADC 期限切れ", "unexpected title: \(n.calls[0].title)")
    assert(n.calls[0].account == "user@example.com", "unexpected account: \(n.calls[0].account ?? "nil")")
    assert(n.calls[0].identifier == "check-gcloud-adc-user@example.com", "unexpected identifier: \(n.calls[0].identifier)")
    assert(n.calls[0].isTest == false, "expected isTest to be false")
}

test("check: one account expired, already delivered -> no notification") {
    let (app, n, c, d) = makeTestApp()
    c.expiredAccounts = ["user@example.com"]
    d.deliveredIdentifiers = ["check-gcloud-adc-user@example.com"]

    app.check()

    assert(n.calls.isEmpty, "expected no notification")
}

test("check: multiple accounts expired -> sends multiple notifications") {
    let (app, n, c, d) = makeTestApp()
    c.expiredAccounts = ["user1@example.com", "user2@example.com"]
    d.deliveredIdentifiers = []

    app.check()

    assert(n.calls.count == 2, "expected 2 notifications, got \(n.calls.count)")
    assert(n.calls[0].account == "user1@example.com", "unexpected first account")
    assert(n.calls[1].account == "user2@example.com", "unexpected second account")
}

test("check: multiple expired, one already delivered -> sends only new") {
    let (app, n, c, d) = makeTestApp()
    c.expiredAccounts = ["user1@example.com", "user2@example.com"]
    d.deliveredIdentifiers = ["check-gcloud-adc-user1@example.com"]

    app.check()

    assert(n.calls.count == 1, "expected 1 notification, got \(n.calls.count)")
    assert(n.calls[0].account == "user2@example.com", "unexpected account")
}

test("scopes: default includes calendar and drive") {
    let resolved = Scopes.resolve([:])
    assert(resolved == Scopes.defaultScopes, "expected default scopes")
    assert(resolved.contains("https://www.googleapis.com/auth/calendar.readonly"), "missing calendar scope")
    assert(resolved.contains("https://www.googleapis.com/auth/drive.readonly"), "missing drive scope")
}

test("scopes: env override (comma/space separated) wins") {
    let env = ["CHECK_GCLOUD_ADC_SCOPES": "openid, https://example.com/a  https://example.com/b"]
    let resolved = Scopes.resolve(env)
    assert(resolved == ["openid", "https://example.com/a", "https://example.com/b"], "unexpected parse: \(resolved)")
    assert(Scopes.joined(env) == "openid,https://example.com/a,https://example.com/b", "unexpected join: \(Scopes.joined(env))")
}

test("scopes: empty env falls back to default") {
    let resolved = Scopes.resolve(["CHECK_GCLOUD_ADC_SCOPES": "   "])
    assert(resolved == Scopes.defaultScopes, "expected fallback to default")
}

test("scopes: requiredForCheck drops openid") {
    let required = Scopes.requiredForCheck([:])
    assert(!required.contains("openid"), "openid should be excluded from check set")
    assert(required.contains("https://www.googleapis.com/auth/calendar.readonly"), "calendar should remain")
}

test("reauth: ADC command sets scopes explicitly") {
    let cmd = GcloudReauth.command(account: nil, environment: [:])
    assert(
        cmd == "gcloud auth application-default login --scopes='\(Scopes.joined([:]))'",
        "unexpected ADC command: \(cmd)"
    )
    assert(cmd.contains("calendar.readonly"), "ADC reauth must request calendar scope")
    assert(cmd.contains("drive.readonly"), "ADC reauth must request drive scope")
}

test("reauth: account command reauths CLI then sets ADC scopes") {
    let cmd = GcloudReauth.command(account: "user@example.com", environment: [:])
    assert(cmd.hasPrefix("gcloud auth login 'user@example.com' && "), "unexpected prefix: \(cmd)")
    assert(cmd.contains("application-default login --scopes='"), "account reauth must set ADC scopes")
    assert(cmd.contains("calendar.readonly"), "account reauth must request calendar scope")
    assert(cmd.contains("drive.readonly"), "account reauth must request drive scope")
    // scope 上書きを招く素の --update-adc を使わないこと。
    assert(!cmd.contains("--update-adc"), "must not rely on --update-adc (drops calendar/drive)")
}

test("reauth: account name with single quote is escaped") {
    let cmd = GcloudReauth.command(account: "a'b@example.com", environment: [:])
    assert(cmd.hasPrefix("gcloud auth login 'a'\\''b@example.com' && "), "unexpected escaping: \(cmd)")
}

test("test: sends test notification") {
    let (app, n, _, _) = makeTestApp()

    app.test()

    assert(n.calls.count == 1, "expected 1 notification, got \(n.calls.count)")
    assert(n.calls[0].title == "Test Notification" || n.calls[0].title == "テスト通知", "unexpected title: \(n.calls[0].title)")
    assert(n.calls[0].isTest == true, "expected isTest to be true")
}

print("\n\(passed) passed, \(failed) failed")

if failed > 0 {
    exit(1)
}
