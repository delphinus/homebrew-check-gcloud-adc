import CheckGcloudADCLib
import Foundation

struct NotifyCall {
    let title: String
    let message: String
    let isTest: Bool
}

class MockNotifier: Notifier {
    var calls: [NotifyCall] = []

    func send(title: String, message: String, isTest: Bool) {
        calls.append(NotifyCall(title: title, message: message, isTest: isTest))
    }
}

class MockADCChecker: ADCChecker {
    var valid = false

    func check() -> Bool { valid }
}

class MockDeliveryChecker: DeliveryChecker {
    var delivered = false

    func isDelivered() -> Bool { delivered }
}

class MockActionWaiter: ActionWaiter {
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

test("check: ADC valid -> no notification") {
    let (app, n, c, _) = makeTestApp()
    c.valid = true

    app.check()

    assert(n.calls.isEmpty, "expected no notification")
}

test("check: ADC invalid, not delivered -> sends notification") {
    let (app, n, c, d) = makeTestApp()
    c.valid = false
    d.delivered = false

    app.check()

    assert(n.calls.count == 1, "expected 1 notification, got \(n.calls.count)")
    assert(n.calls[0].title == "Google Cloud ADC Expired", "unexpected title: \(n.calls[0].title)")
    assert(n.calls[0].isTest == false, "expected isTest to be false")
}

test("check: ADC invalid, already delivered -> no notification") {
    let (app, n, c, d) = makeTestApp()
    c.valid = false
    d.delivered = true

    app.check()

    assert(n.calls.isEmpty, "expected no notification")
}

test("runTest: sends test notification") {
    let (app, n, _, _) = makeTestApp()

    app.test()

    assert(n.calls.count == 1, "expected 1 notification, got \(n.calls.count)")
    assert(n.calls[0].title == "Test Notification", "unexpected title: \(n.calls[0].title)")
    assert(n.calls[0].isTest == true, "expected isTest to be true")
}

print("\n\(passed) passed, \(failed) failed")

if failed > 0 {
    exit(1)
}
