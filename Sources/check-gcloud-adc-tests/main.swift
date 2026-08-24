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

test("accounts: unset allowlist -> no filtering (all accounts)") {
    let allow = Accounts.allowlist(environment: [:], configText: nil)
    assert(allow.isEmpty, "expected empty allowlist")
    let filtered = Accounts.filter(["a@example.com", "b@example.com"], allowlist: allow)
    assert(filtered == ["a@example.com", "b@example.com"], "empty allowlist must pass through: \(filtered)")
}

test("accounts: env allowlist (comma/space separated) wins over file") {
    let env = ["CHECK_GCLOUD_ADC_ACCOUNTS": "a@example.com, b@example.com"]
    let allow = Accounts.allowlist(environment: env, configText: "c@example.com\n")
    assert(allow == ["a@example.com", "b@example.com"], "env must win: \(allow)")
}

test("accounts: file used when env unset (comments/blank lines ignored)") {
    let text = """
    # accounts to check
    a@example.com

    b@example.com  # inline comment
    """
    let allow = Accounts.allowlist(environment: [:], configText: text)
    assert(allow == ["a@example.com", "b@example.com"], "unexpected file parse: \(allow)")
}

test("accounts: filter keeps only allowlisted accounts") {
    let filtered = Accounts.filter(
        ["keep@example.com", "drop@example.com"],
        allowlist: ["keep@example.com"]
    )
    assert(filtered == ["keep@example.com"], "unexpected filter result: \(filtered)")
}

test("accounts: resolveAllowlist reads config file via XDG_CONFIG_HOME") {
    let dir = NSTemporaryDirectory() + "check-gcloud-adc-test-\(getpid())"
    let cfgDir = dir + "/check-gcloud-adc"
    try? FileManager.default.createDirectory(atPath: cfgDir, withIntermediateDirectories: true)
    let path = cfgDir + "/accounts"
    try? "# comment\nkeep@example.com\n".write(toFile: path, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(atPath: dir) }

    let allow = Accounts.resolveAllowlist(["XDG_CONFIG_HOME": dir])
    assert(allow == ["keep@example.com"], "expected file to be read: \(allow)")
    // env が有効ならファイルより env が優先される。
    let allow2 = Accounts.resolveAllowlist([
        "XDG_CONFIG_HOME": dir,
        "CHECK_GCLOUD_ADC_ACCOUNTS": "env@example.com",
    ])
    assert(allow2 == ["env@example.com"], "env must win over file: \(allow2)")
}

test("accounts: default config path honors XDG_CONFIG_HOME then HOME") {
    let xdg = Accounts.defaultConfigPath(["XDG_CONFIG_HOME": "/tmp/xdg"])
    assert(xdg == "/tmp/xdg/check-gcloud-adc/accounts", "unexpected XDG path: \(xdg)")
    let home = Accounts.defaultConfigPath(["HOME": "/Users/foo"])
    assert(home == "/Users/foo/.config/check-gcloud-adc/accounts", "unexpected HOME path: \(home)")
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

test("browser: default executable is Google Chrome, empty env disables it") {
    assert(Browser.resolveExecutable([:]) == Browser.defaultExecutable, "expected the default Chrome path")
    assert(Browser.resolveExecutable(["CHECK_GCLOUD_ADC_BROWSER": "/tmp/brave"]) == "/tmp/brave", "env must win")
    assert(Browser.resolveExecutable(["CHECK_GCLOUD_ADC_BROWSER": "  "]) == nil, "empty env must disable the shim")
}

test("browser: profile path honors env, then XDG_CACHE_HOME, then HOME") {
    let explicit = Browser.resolveProfile(["CHECK_GCLOUD_ADC_BROWSER_PROFILE": "/tmp/p"])
    assert(explicit == "/tmp/p", "unexpected explicit profile: \(explicit)")
    let xdg = Browser.resolveProfile(["XDG_CACHE_HOME": "/tmp/xdg"])
    assert(xdg == "/tmp/xdg/check-gcloud-adc/browser-profile", "unexpected XDG profile: \(xdg)")
    let home = Browser.resolveProfile(["HOME": "/Users/foo"])
    assert(home == "/Users/foo/.cache/check-gcloud-adc/browser-profile", "unexpected HOME profile: \(home)")
}

test("browser: shim pins the profile and always opens a new window") {
    let script = Browser.shimScript(executable: "/tmp/Chrome", profile: "/tmp/prof")
    assert(script.contains("--user-data-dir='/tmp/prof'"), "shim must pin --user-data-dir: \(script)")
    assert(script.contains("--new-window"), "shim must not reuse an existing window")
    assert(script.contains("exec /usr/bin/open"), "non-URL invocations must fall back to open")
}

test("browser: shim escapes single quotes in paths") {
    let script = Browser.shimScript(executable: "/tmp/a'b/Chrome", profile: "/tmp/prof")
    assert(script.contains("'/tmp/a'\\''b/Chrome'"), "unexpected escaping: \(script)")
}

test("browser: wrap exports the shim and closes the window afterwards") {
    let session = Browser.Session(shimDir: "/tmp/shim", profile: "/tmp/prof")
    let wrapped = Browser.wrap(command: "gcloud auth login", session: session)
    assert(wrapped.contains("export BROWSER='/tmp/shim/open-url'"), "must set $BROWSER: \(wrapped)")
    assert(wrapped.contains("export PATH='/tmp/shim':\"$PATH\""), "must prepend the shim to PATH: \(wrapped)")
    assert(wrapped.hasSuffix("\ngcloud auth login"), "must end with the original command: \(wrapped)")
    assert(wrapped.contains("/bin/rm -rf '/tmp/shim'"), "must clean up the shim: \(wrapped)")
    // gcloud が落ちても専用ウィンドウが残らないよう EXIT トラップに載せる。
    assert(wrapped.contains("trap __ccga_cleanup EXIT"), "cleanup must run on EXIT: \(wrapped)")
    // zsh はトラップの後も処理を続行するので、シグナル側は明示的に抜けること。
    assert(wrapped.contains("exit 143") && wrapped.contains("exit 130"), "signal traps must exit: \(wrapped)")
    // 自分の argv を撃たないよう、コマンドラインのパターン照合は使わない。
    assert(!wrapped.contains("pkill -TERM -f"), "must not pattern-match command lines: \(wrapped)")
    assert(wrapped.contains("/tmp/shim/chrome.pid"), "must track Chrome by pid: \(wrapped)")
}

test("browser: shim records the Chrome pid without overwriting it") {
    let script = Browser.shimScript(executable: "/tmp/Chrome", profile: "/tmp/prof")
    assert(script.contains("chrome.pid"), "shim must record the Chrome pid: \(script)")
    // 2 度目の起動は走っているインスタンスに取り次いですぐ終わる。上書きさせない。
    assert(script.contains("[ -s \"$(dirname \"$0\")/chrome.pid\" ] ||"), "must not overwrite the pid: \(script)")
}

test("browser: wrap watches the window and stops gcloud when it is closed") {
    let session = Browser.Session(shimDir: "/tmp/shim", profile: "/tmp/prof")
    let wrapped = Browser.wrap(command: "gcloud auth login", session: session)
    assert(wrapped.contains("kill -0 \"$__ccga_chrome\""), "must watch the Chrome pid: \(wrapped)")
    // gcloud だけでなくプロセスグループごと。後続のコマンドへ進ませない。
    assert(wrapped.contains("kill -TERM -$$"), "must stop the whole group when the window is gone: \(wrapped)")
}

test("browser: window size parses WxH, empty env leaves it to Chrome") {
    assert(Browser.resolveWindowSize([:]) == Browser.defaultWindowSize, "expected the default size")
    assert(Browser.resolveWindowSize(["CHECK_GCLOUD_ADC_BROWSER_WINDOW": ""]) == nil, "empty env must not set a size")
    assert(
        Browser.resolveWindowSize(["CHECK_GCLOUD_ADC_BROWSER_WINDOW": " 480 X 640 "]) == CGSize(width: 480, height: 640),
        "must accept spaces and an uppercase X"
    )
    // 壊れた値は既定に落とす (再認証そのものを失敗させない)。
    assert(Browser.resolveWindowSize(["CHECK_GCLOUD_ADC_BROWSER_WINDOW": "nonsense"]) == Browser.defaultWindowSize, "must fall back")
    assert(Browser.parseWindowSize("0x100") == nil, "zero is not a size")
}

test("browser: window is centered on the target screen") {
    // 主画面 2560x1440、上 30 がメニューバー、下 96 が Dock。
    let visible = CGRect(x: 0, y: 96, width: 2560, height: 1314)
    let p = Browser.centeredPlacement(size: CGSize(width: 600, height: 800), visibleFrame: visible, primaryTopY: 1440)
    assert(p.width == 600 && p.height == 800, "size must be kept: \(p)")
    assert(p.x == 980, "must be centered horizontally: \(p.x)")
    // 可視領域の中心 y は 753、ウィンドウ上端は 1153 (macOS 座標) → 上から 287。
    assert(p.y == 287, "must be centered vertically in Chrome's top-down coordinates: \(p.y)")
}

test("browser: window on a secondary screen uses the primary screen's origin") {
    // 主画面の右にある縦置きの画面。原点は主画面の左下のまま。
    let visible = CGRect(x: 2560, y: -570, width: 1440, height: 2560)
    let p = Browser.centeredPlacement(size: CGSize(width: 600, height: 800), visibleFrame: visible, primaryTopY: 1440)
    assert(p.x == 2980, "must be centered on the secondary screen: \(p.x)")
    // 上端は macOS 座標で 1110 → 主画面上端 1440 から 330 下。
    assert(p.y == 330, "y must be relative to the primary screen top: \(p.y)")
}

test("browser: window shrinks to fit a small screen") {
    let visible = CGRect(x: 0, y: 0, width: 800, height: 600)
    let p = Browser.centeredPlacement(size: CGSize(width: 600, height: 800), visibleFrame: visible, primaryTopY: 600)
    assert(p.width == 600, "600 fits in 800 - 2*40: \(p.width)")
    assert(p.height == 520, "800 must shrink to 600 - 2*40: \(p.height)")
    assert(p.x == 100 && p.y == 40, "must stay centered after shrinking: \(p)")
}

test("browser: window arguments reach the shim") {
    let args = Browser.windowArguments(
        [:],
        screen: (visibleFrame: CGRect(x: 0, y: 96, width: 2560, height: 1314), primaryTopY: 1440)
    )
    assert(args == ["--window-size=600,800", "--window-position=980,287"], "unexpected args: \(args)")
    let script = Browser.shimScript(executable: "/tmp/Chrome", profile: "/tmp/prof", windowArguments: args)
    assert(script.contains("'--window-size=600,800'"), "size must reach the shim: \(script)")
    assert(script.contains("'--window-position=980,287'"), "position must reach the shim: \(script)")
    // 画面が分からない環境では大きさだけ渡し、位置は Chrome に任せる。
    let sizeOnly = Browser.windowArguments([:], screen: nil)
    assert(sizeOnly == ["--window-size=600,800"], "unexpected args without a screen: \(sizeOnly)")
    assert(Browser.windowArguments(["CHECK_GCLOUD_ADC_BROWSER_WINDOW": ""], screen: nil).isEmpty, "empty env means no flags")
}

test("browser: parsePIDs reads pgrep output") {
    assert(Browser.parsePIDs("123\n456\n") == [123, 456], "unexpected parse")
    assert(Browser.parsePIDs("").isEmpty, "empty output means no pids")
    assert(Browser.parsePIDs("nonsense\n789").map(Int.init) == [789], "must skip garbage")
}

test("browser: terminateStaleSessions kills the whole process group") {
    // ラッパーを模したプロセスグループ (親 + 子) を作り、親だけを見つけて
    // グループごと落とせることを確かめる。子が孤児にならないのが要点。
    let pattern = "check-gcloud-adc-group-kill-test-\(getpid())"
    let marker = NSTemporaryDirectory() + pattern
    let script = "sleep 120 & echo $! > \(marker).child; sleep 120"
    let parent = Process()
    parent.launchPath = "/bin/sh"
    parent.arguments = ["-c", script]
    try? parent.run()
    Thread.sleep(forTimeInterval: 1)

    let child = (try? String(contentsOfFile: marker + ".child", encoding: .utf8))
        .flatMap { pid_t($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    defer { try? FileManager.default.removeItem(atPath: marker + ".child") }
    guard let child = child else {
        assert(false, "could not read the child pid")
        return
    }

    // SIGKILL 等で置き去りになった shim ディレクトリも掃除される。
    let orphan = NSTemporaryDirectory() + Browser.shimPrefix + "orphan-test"
    try? FileManager.default.createDirectory(atPath: orphan, withIntermediateDirectories: true)

    let killed = Browser.terminateStaleSessions(
        profile: "/tmp/check-gcloud-adc-no-such-profile",
        pattern: pattern
    )
    assert(killed.contains(parent.processIdentifier), "expected the wrapper pid, got \(killed)")
    Thread.sleep(forTimeInterval: 1)
    assert(kill(child, 0) != 0, "the child must be killed along with its group")
    assert(!parent.isRunning, "the wrapper must be killed")
    assert(!FileManager.default.fileExists(atPath: orphan), "orphaned shim dirs must be removed")
}

test("browser: wrapped command preserves the exit code and cleans up") {
    let session = Browser.Session(shimDir: "/tmp/check-gcloud-adc-wrap-test", profile: "/tmp/check-gcloud-adc-wrap-prof")
    try? FileManager.default.createDirectory(atPath: session.shimDir, withIntermediateDirectories: true)
    let wrapped = Browser.wrap(command: "/bin/sh -c 'exit 7'", session: session)

    let task = Process()
    task.launchPath = "/bin/zsh"
    task.arguments = ["-l", "-c", wrapped]
    try? task.run()
    task.waitUntilExit()

    assert(task.terminationStatus == 7, "expected exit 7, got \(task.terminationStatus)")
    assert(!FileManager.default.fileExists(atPath: session.shimDir), "shim dir must be removed")
}

test("browser: default extension is 1Password, empty env opens nothing") {
    assert(Browser.resolveExtensions([:]) == Browser.defaultExtensions, "expected the default extension list")
    assert(Browser.defaultExtensions == ["aeblfdkhhhdcdjpifhhbdiojplfjncoa"], "expected the 1Password extension id")
    assert(Browser.resolveExtensions(["CHECK_GCLOUD_ADC_BROWSER_EXTENSIONS": ""]).isEmpty, "empty env must open nothing")
    let two = Browser.resolveExtensions(["CHECK_GCLOUD_ADC_BROWSER_EXTENSIONS": "aaa, bbb"])
    assert(two == ["aaa", "bbb"], "unexpected parse: \(two)")
}

test("browser: setup pages open only for extensions that are missing") {
    let missing = Browser.setupURLs(profile: "/tmp/p", environment: [:]) { _ in false }
    assert(missing == ["https://chromewebstore.google.com/detail/aeblfdkhhhdcdjpifhhbdiojplfjncoa"], "unexpected: \(missing)")
    let installed = Browser.setupURLs(profile: "/tmp/p", environment: [:]) { _ in true }
    assert(installed.isEmpty, "must stop nagging once installed: \(installed)")
}

test("browser: shim opens setup pages as extra tabs, auth URL first") {
    let script = Browser.shimScript(
        executable: "/tmp/Chrome",
        profile: "/tmp/prof",
        setupURLs: ["https://example.com/ext"]
    )
    assert(
        script.contains("--new-window \"$url\" 'https://example.com/ext'"),
        "setup pages must follow the auth URL: \(script)"
    )
    let bare = Browser.shimScript(executable: "/tmp/Chrome", profile: "/tmp/prof")
    assert(bare.contains("--new-window \"$url\" >"), "no setup pages means no extra args: \(bare)")
}

test("browser: makeSession links native messaging hosts into the profile") {
    let dir = NSTemporaryDirectory() + "check-gcloud-adc-nmh-test-\(getpid())"
    let fakeHome = dir + "/home"
    let hosts = fakeHome + "/Library/Application Support/Google/Chrome/NativeMessagingHosts"
    try? FileManager.default.createDirectory(atPath: hosts, withIntermediateDirectories: true)
    try? "{}".write(toFile: hosts + "/com.1password.1password.json", atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(atPath: dir) }

    guard let session = Browser.makeSession([
        "CHECK_GCLOUD_ADC_BROWSER": "/bin/echo",
        "CHECK_GCLOUD_ADC_BROWSER_PROFILE": dir + "/profile",
        "HOME": fakeHome,
    ]) else {
        assert(false, "expected a session")
        return
    }
    defer { try? FileManager.default.removeItem(atPath: session.shimDir) }

    let linked = session.profile + "/NativeMessagingHosts/com.1password.1password.json"
    assert(FileManager.default.fileExists(atPath: linked), "1Password manifest must be reachable from the profile")
    // 拡張機能が未導入なのでストアページが付く。
    assert(session.setupURLs.count == 1, "expected the 1Password store page: \(session.setupURLs)")
}

test("browser: native messaging links coexist with the directory Chrome creates") {
    let dir = NSTemporaryDirectory() + "check-gcloud-adc-nmh2-test-\(getpid())"
    let fm = FileManager.default
    let fakeHome = dir + "/home"
    let source = fakeHome + "/Library/Application Support/Google/Chrome/NativeMessagingHosts"
    let profile = dir + "/profile"
    try? fm.createDirectory(atPath: source, withIntermediateDirectories: true)
    try? "{}".write(toFile: source + "/com.1password.1password.json", atomically: true, encoding: .utf8)
    try? "{}".write(toFile: source + "/com.other.host.json", atomically: true, encoding: .utf8)
    // Chrome は起動時にこのディレクトリを自分で作る。既に在っても張れること。
    try? fm.createDirectory(atPath: profile + "/NativeMessagingHosts", withIntermediateDirectories: true)
    defer { try? fm.removeItem(atPath: dir) }

    let first = Browser.linkNativeMessagingHosts(profile: profile, environment: ["HOME": fakeHome])
    assert(first == 2, "expected 2 links, got \(first)")
    assert(
        fm.fileExists(atPath: profile + "/NativeMessagingHosts/com.1password.1password.json"),
        "1Password manifest must be linked even though the directory already existed"
    )
    // 2 回目は何も足さない (冪等)。
    let second = Browser.linkNativeMessagingHosts(profile: profile, environment: ["HOME": fakeHome])
    assert(second == 0, "expected no new links on the second run, got \(second)")
}

test("browser: makeSession returns nil when disabled") {
    assert(Browser.makeSession(["CHECK_GCLOUD_ADC_BROWSER": ""]) == nil, "empty env must disable the shim")
}

test("browser: makeSession writes an executable shim and an open symlink") {
    let dir = NSTemporaryDirectory() + "check-gcloud-adc-browser-test-\(getpid())"
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(atPath: dir) }

    // 実行可能ファイルとして通るものなら何でもよい (Chrome がない環境でも回るように)。
    guard let session = Browser.makeSession([
        "CHECK_GCLOUD_ADC_BROWSER": "/bin/echo",
        "CHECK_GCLOUD_ADC_BROWSER_PROFILE": dir + "/profile",
    ]) else {
        assert(false, "expected a session")
        return
    }
    defer { try? FileManager.default.removeItem(atPath: session.shimDir) }

    let fm = FileManager.default
    assert(session.profile == dir + "/profile", "unexpected profile: \(session.profile)")
    assert(fm.fileExists(atPath: session.profile), "profile directory must be created")
    assert(fm.isExecutableFile(atPath: session.shimDir + "/open-url"), "shim must be executable")
    assert(fm.isExecutableFile(atPath: session.shimDir + "/open"), "open shim must be executable")

    // shim を実際に叩いて、URL が渡ることと即座に終わることを確かめる。
    let task = Process()
    task.launchPath = session.shimDir + "/open-url"
    task.arguments = ["https://example.com/"]
    let pipe = Pipe()
    task.standardOutput = pipe
    try? task.run()
    task.waitUntilExit()
    assert(task.terminationStatus == 0, "shim must exit 0, got \(task.terminationStatus)")
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
