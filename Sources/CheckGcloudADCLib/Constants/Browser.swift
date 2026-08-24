import Foundation

/// 再認証を「専用プロファイルの Chrome ウィンドウ」で行うための設定。
///
/// 素のまま `gcloud auth ... login` を走らせると、既定ブラウザの「最後に使った
/// ウィンドウ / プロファイル」に認証タブが生える。どのプロファイルで認証したかが
/// ブレるうえ、終わってもタブが残る。そこで gcloud には専用のブラウザ起動
/// スクリプト (shim) を渡す。
///
/// - `--user-data-dir` を固定パスにした Chrome インスタンスで開く。普段使いの
///   Chrome とは別プロセス・別プロファイルになるので、既存ウィンドウを再利用しない。
/// - プロファイルのディレクトリ自体は残すので、Google のログインセッションと
///   拡張機能は次回の再認証に引き継がれる (= プロファイルが固定される)。
/// - gcloud が終わったら、その `--user-data-dir` を持つプロセスだけを終了させる。
///
/// 拡張機能は user-data-dir の中のプロファイル単位なので、専用プロファイルは
/// 素のままだと 1Password も入っていない。Google の再認証 (`invalid_rapt`) は
/// パスワードや 2 要素をその都度要求してくるため、パスワードマネージャが使えないと
/// 手打ちを強いられ、ドメイン照合による phishing 耐性も失われる。そこで、
///
/// - 必要な拡張機能がまだ入っていなければ、そのインストールページを認証 URL と
///   一緒に開く (既定は 1Password。`CHECK_GCLOUD_ADC_BROWSER_EXTENSIONS` で変更可)
/// - 1Password デスクトップアプリとの連携に要る native messaging の manifest が
///   専用プロファイルからも引けるよう、既定の Chrome のものへ symlink を張る
///
/// を行う。拡張機能の導入とデスクトップアプリの承認は初回に一度だけ手で行えば、
/// プロファイルが永続なので以後ずっと効く。
///
/// gcloud へは 2 経路で渡す。どちらの流儀の実装でも拾えるようにするため:
///
/// 1. `$BROWSER` … gcloud が使う Python の `webbrowser` モジュールが見る。
/// 2. `PATH` 上の `open` … macOS で `open <url>` を直に叩く実装向けの保険。
///
/// Safari を使わないのは、Safari 17+ のプロファイルを CLI / AppleScript から指定
/// する手段が無く、「どのプロファイルで開くか」を固定できないため。`open -na Safari`
/// も複数インスタンスにはならず既存ウィンドウを前面化するだけになる。
public enum Browser {
    /// Chrome 系ブラウザの実行ファイルパスの上書き。空文字を設定すると shim を
    /// 使わず既定ブラウザに任せる (従来の挙動)。
    public static let envKey = "CHECK_GCLOUD_ADC_BROWSER"

    /// プロファイル (`--user-data-dir`) の置き場所の上書き。
    public static let profileEnvKey = "CHECK_GCLOUD_ADC_BROWSER_PROFILE"

    /// 専用プロファイルに入っていなければインストールページを開く拡張機能の ID
    /// (カンマ / 空白区切り)。空文字を設定すると何も開かない。
    public static let extensionsEnvKey = "CHECK_GCLOUD_ADC_BROWSER_EXTENSIONS"

    /// 既定の実行ファイル。
    public static let defaultExecutable = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

    /// 既定でインストールを促す拡張機能。1Password – パスワード保管庫。
    public static let defaultExtensions = ["aeblfdkhhhdcdjpifhhbdiojplfjncoa"]

    /// 既定の Chrome が native messaging の manifest を置く場所。`--user-data-dir`
    /// を変えても Chrome はここを見る実装だが、user-data-dir 相対に見る版もあるため
    /// 専用プロファイル側に symlink を張って両方に備える。
    public static let nativeMessagingHostsDirName = "NativeMessagingHosts"

    /// gcloud 終了後、ウィンドウを閉じるまでの猶予 (秒)。最後のリダイレクトを
    /// 取りこぼさないための保険。
    public static let closeGraceSeconds = 1

    /// 書き出した shim の場所と、使うプロファイルの組。
    public struct Session {
        public let shimDir: String
        public let profile: String
        /// 認証 URL と一緒に開くセットアップ用ページ (未導入の拡張機能のストアページ)。
        public let setupURLs: [String]

        public init(shimDir: String, profile: String, setupURLs: [String] = []) {
            self.shimDir = shimDir
            self.profile = profile
            self.setupURLs = setupURLs
        }
    }

    /// 使う実行ファイルを解決する。env に空文字が入っていれば nil (= 機能を無効化)。
    public static func resolveExecutable(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        guard let raw = environment[envKey] else { return defaultExecutable }
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// プロファイルのパスを返す (`$XDG_CACHE_HOME` があれば優先、無ければ `~/.cache`)。
    public static func resolveProfile(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        if let raw = environment[profileEnvKey] {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { return trimmed }
        }
        let base: String
        if let xdg = environment["XDG_CACHE_HOME"], !xdg.isEmpty {
            base = xdg
        } else {
            let home = environment["HOME"] ?? NSHomeDirectory()
            base = (home as NSString).appendingPathComponent(".cache")
        }
        return (base as NSString).appendingPathComponent("check-gcloud-adc/browser-profile")
    }

    /// インストールを促す拡張機能の ID を解決する。空文字が入っていれば空配列。
    public static func resolveExtensions(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String] {
        guard let raw = environment[extensionsEnvKey] else { return defaultExtensions }
        return raw
            .split(whereSeparator: { $0 == "," || $0 == " " })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Chrome ウェブストアの拡張機能ページ。ID だけでも正規 URL にリダイレクトされる。
    public static func extensionStoreURL(_ identifier: String) -> String {
        "https://chromewebstore.google.com/detail/\(identifier)"
    }

    /// プロファイルにまだ入っていない拡張機能のストアページを返す。
    ///
    /// 「新規プロファイルか」ではなく「実際に入っているか」で判断するので、
    /// 既に作ってしまった素のプロファイルも次の再認証で拾える。導入が済めば
    /// 開かなくなる。開かれたくない場合は `CHECK_GCLOUD_ADC_BROWSER_EXTENSIONS`
    /// に空文字を設定する。
    public static func setupURLs(
        profile: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        isInstalled: (String) -> Bool
    ) -> [String] {
        resolveExtensions(environment)
            .filter { !isInstalled($0) }
            .map(extensionStoreURL)
    }

    /// 専用プロファイル (`--user-data-dir` 直下の `Default`) に拡張機能が入っているか。
    static func isExtensionInstalled(profile: String, identifier: String) -> Bool {
        let path = (profile as NSString)
            .appendingPathComponent("Default/Extensions/\(identifier)")
        return FileManager.default.fileExists(atPath: path)
    }

    /// shim スクリプトの中身。
    ///
    /// - Parameter setupURLs: 認証 URL と一緒に開くセットアップ用のページ。同じ
    ///   ウィンドウの別タブとして開く。認証 URL を先に置いてあるので、どちらが
    ///   手前になっても認証タブは必ず 1 番目のタブにいる。
    ///
    /// 起動した Chrome の PID を `chrome.pid` に残す。ラッパー側はこれを見て
    /// 「ウィンドウが閉じられたか」を判定し、終了時にはこの PID だけを落とす。
    /// コマンドラインのパターン照合を使わないのは、ラッパーの argv 自体に
    /// `--user-data-dir=...` が含まれてしまい、`pkill -f` が自分を撃つため。
    ///
    /// gcloud が 2 度目の URL を開いた場合、その起動プロセスは走っている
    /// インスタンスへ取り次いですぐ終わる。PID を上書きすると「閉じられた」と
    /// 誤判定するので、既に記録があれば書かない。
    public static func shimScript(
        executable: String,
        profile: String,
        setupURLs: [String] = []
    ) -> String {
        let extra = setupURLs.isEmpty ? "" : " " + setupURLs.map(quote).joined(separator: " ")
        return """
        #!/bin/sh
        # check-gcloud-adc が再認証中だけ gcloud に使わせるブラウザ。
        # 引数のうち URL に見えるものだけを拾う (`open -a Foo <url>` 形式の呼ばれ方対策)。
        url=
        for a in "$@"; do
          case $a in http://* | https://*) url=$a ;; esac
        done
        # URL が無い呼び出し (ファイルを開く等) は素の open に流す。
        [ -n "$url" ] || exec /usr/bin/open "$@"
        \(quote(executable)) \\
          --user-data-dir=\(quote(profile)) \\
          --no-first-run \\
          --no-default-browser-check \\
          --no-service-autorun \\
          --hide-crash-restore-bubble \\
          --new-window "$url"\(extra) > /dev/null 2>&1 &
        [ -s "$(dirname "$0")/\(chromePIDFileName)" ] || echo $! > "$(dirname "$0")/\(chromePIDFileName)"
        exit 0
        """
    }

    /// shim が起動した Chrome の PID を書き出すファイル名 (shim ディレクトリの中)。
    public static let chromePIDFileName = "chrome.pid"

    /// 専用プロファイルから native messaging の manifest を引けるようにする。
    ///
    /// 1Password 拡張はデスクトップアプリと native messaging で話すが、その manifest
    /// (`com.1password.1password.json`) は既定の Chrome の場所にしか置かれていない。
    /// Chrome は `--user-data-dir` 直下の `NativeMessagingHosts` を見る (実際に空の
    /// ディレクトリを自分で作る) ので、そこへ manifest 単位で symlink を張る。
    ///
    /// ディレクトリごと symlink にしないのは、Chrome が先にディレクトリを作って
    /// しまうため。個別ファイルなら Chrome が作ったディレクトリと共存できる。
    ///
    /// - Returns: 新しく張った symlink の数。
    @discardableResult
    public static func linkNativeMessagingHosts(
        profile: String,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Int {
        let fm = FileManager.default
        let home = environment["HOME"] ?? NSHomeDirectory()
        let source = (home as NSString)
            .appendingPathComponent("Library/Application Support/Google/Chrome/\(nativeMessagingHostsDirName)")
        let destination = (profile as NSString).appendingPathComponent(nativeMessagingHostsDirName)

        guard let manifests = try? fm.contentsOfDirectory(atPath: source) else { return 0 }

        var linked = 0
        do {
            try fm.createDirectory(atPath: destination, withIntermediateDirectories: true)
            for manifest in manifests where manifest.hasSuffix(".json") {
                let target = (destination as NSString).appendingPathComponent(manifest)
                // 既に何か置かれているなら触らない (利用者が用意したものを壊さない)。
                guard !fm.fileExists(atPath: target) else { continue }
                try fm.createSymbolicLink(
                    atPath: target,
                    withDestinationPath: (source as NSString).appendingPathComponent(manifest)
                )
                linked += 1
            }
        } catch {
            fputs("could not link native messaging hosts: \(error.localizedDescription)\n", stderr)
        }
        return linked
    }

    /// gcloud のコマンドを shim 込みに包む。
    ///
    /// `zsh -l` は rc ファイルを読み直すので、`export` は Process の environment
    /// ではなくコマンド文字列側に置く。そうしないと rc の `path=(...)` に
    /// PATH を作り直されて shim が消えることがある。
    ///
    /// 併せて 2 つの後始末を仕込む。
    ///
    /// - **EXIT トラップ**: gcloud が終わったら (途中で落ちても、こちらが終了させ
    ///   られても) 専用ウィンドウと shim を片付ける。zsh の EXIT トラップは終了
    ///   ステータスを書き換えないので、gcloud の終了コードはそのまま返る。
    /// - **見張り**: 専用ウィンドウを利用者が閉じた (= Chrome が終了した) 場合、
    ///   gcloud はコールバックを待ち続けて永久に終わらない。Chrome の PID を
    ///   `kill -0` で監視し、消えたら gcloud を終わらせる。
    ///
    /// PID で扱うのが要点。`pkill -f '--user-data-dir=...'` のようなコマンドライン
    /// のパターン照合は、ラッパー自身の argv にもその文字列が含まれるため自分を
    /// 撃ってしまう。前回の残骸の掃除は、argv にパターンを持たない Swift 側
    /// (`terminateStaleSessions`) で行う。
    public static func wrap(command: String, session: Session) -> String {
        let shim = quote(session.shimDir)
        let opener = quote((session.shimDir as NSString).appendingPathComponent("open-url"))
        let pidFile = quote((session.shimDir as NSString).appendingPathComponent(chromePIDFileName))
        return """
        export BROWSER=\(opener)
        export PATH=\(shim):"$PATH"

        __ccga_pid_file=\(pidFile)

        # 専用ウィンドウが閉じられたら gcloud を待たせ続けない。
        __ccga_watch() {
          __ccga_n=0
          while [ $__ccga_n -lt \(browserAppearTimeoutSeconds) ]; do
            [ -s "$__ccga_pid_file" ] && break
            __ccga_n=$((__ccga_n + 1))
            sleep 1
          done
          # ブラウザが出てこなかった (shim が使われなかった) なら何もしない。
          [ -s "$__ccga_pid_file" ] || return 0
          read __ccga_chrome < "$__ccga_pid_file"
          while kill -0 "$__ccga_chrome" 2> /dev/null; do sleep 2; done
          # プロセスグループごと落とす。gcloud だけを落とすと、このシェルが後続の
          # コマンド (`a && b` の b 等) へ進んでしまう。自分がグループのリーダー
          # でなければ $$ と同じ pgid は存在しないので、他所を撃つ心配は無い。
          kill -TERM -$$ 2> /dev/null || /usr/bin/pkill -TERM -P $$ > /dev/null 2>&1
        }

        __ccga_done=0
        __ccga_cleanup() {
          [ "$__ccga_done" = 0 ] || return 0
          __ccga_done=1
          kill "$__ccga_watcher" 2> /dev/null
          sleep \(closeGraceSeconds)
          if [ -s "$__ccga_pid_file" ]; then
            read __ccga_chrome < "$__ccga_pid_file"
            kill -TERM "$__ccga_chrome" 2> /dev/null
          fi
          /bin/rm -rf \(shim)
        }

        __ccga_watch &
        __ccga_watcher=$!
        # zsh はシグナルのトラップを実行したあと処理を続行するので、明示的に
        # 抜ける。そうしないと TERM を受けても gcloud を待ち続けてしまう。
        trap __ccga_cleanup EXIT
        trap '__ccga_cleanup; exit 143' TERM
        trap '__ccga_cleanup; exit 130' INT

        \(command)
        """
    }

    /// 見張りが「ブラウザが出てこなかった」と諦めるまでの秒数。
    public static let browserAppearTimeoutSeconds = 60

    /// shim を一時ディレクトリに書き出す。無効化されている・Chrome が無い・
    /// 書き出しに失敗した場合は nil を返し、呼び出し側は従来どおり既定ブラウザに任せる。
    public static func makeSession(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Session? {
        guard let executable = resolveExecutable(environment) else { return nil }
        let fm = FileManager.default
        guard fm.isExecutableFile(atPath: executable) else {
            fputs("dedicated browser not found, falling back to the default browser: \(executable)\n", stderr)
            return nil
        }

        let profile = resolveProfile(environment)
        let setup = setupURLs(profile: profile, environment: environment) {
            isExtensionInstalled(profile: profile, identifier: $0)
        }
        let shimDir = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent(shimPrefix + UUID().uuidString)
        let opener = (shimDir as NSString).appendingPathComponent("open-url")

        do {
            try fm.createDirectory(atPath: profile, withIntermediateDirectories: true)
            try fm.createDirectory(
                atPath: shimDir,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try shimScript(executable: executable, profile: profile, setupURLs: setup)
                .write(toFile: opener, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: opener)
            // `open <url>` を直に叩く実装向けに PATH 上の open も差し替える。
            try fm.createSymbolicLink(
                atPath: (shimDir as NSString).appendingPathComponent("open"),
                withDestinationPath: "open-url"
            )
        } catch {
            fputs("dedicated browser setup failed: \(error.localizedDescription)\n", stderr)
            try? fm.removeItem(atPath: shimDir)
            return nil
        }

        // 1Password 等がデスクトップアプリと話せるようにする。失敗しても続行する。
        linkNativeMessagingHosts(profile: profile, environment: environment)

        return Session(shimDir: shimDir, profile: profile, setupURLs: setup)
    }

    /// shim ディレクトリ名の前置き。前回の再認証を見つける手掛かりに使う。
    public static let shimPrefix = "check-gcloud-adc-browser-"

    /// 前回の再認証が残っていれば落として、毎回まっさらな状態から始める。
    ///
    /// 利用者が専用ウィンドウを閉じただけだと、`gcloud` はローカルのコールバックを
    /// 待ち続けて終わらず、それを待つラッパーの `zsh` も残る。放っておくと
    /// `open check-gcloud-adc://reauth` のたびに溜まっていくので、始める前に掃除する。
    ///
    /// ラッパーの `zsh` はプロセスグループのリーダーで、`gcloud` は同じグループに
    /// いる。`zsh` だけを落とすと `gcloud` が孤児になって待ち続けるので、
    /// **グループごと**落とす。
    ///
    /// この処理を Swift 側に置いているのは、`pgrep`/`pkill` に渡すパターンが
    /// 自分自身の argv に含まれないようにするため。同じことをラッパーの中でやると
    /// `pkill -f` が自分を撃つ。
    ///
    /// - Parameter pattern: 前回のラッパーを探す `pgrep -f` のパターン。既定は
    ///   shim ディレクトリの前置き。テストが無関係なプロセスを巻き込まないよう
    ///   差し替えられるようにしてある。
    /// - Returns: 落とした前回のラッパーの PID。
    @discardableResult
    public static func terminateStaleSessions(profile: String, pattern: String = shimPrefix) -> [pid_t] {
        let stale = parsePIDs(capture("/usr/bin/pgrep", ["-f", pattern]))
        for pid in stale {
            // まずプロセスグループごと。リーダーでなければ単体で。
            if kill(-pid, SIGTERM) != 0 { kill(pid, SIGTERM) }
        }
        // ラッパーが既に居ない孤児のウィンドウも掃除する。
        run("/usr/bin/pkill", ["-TERM", "-f", "--", "--user-data-dir=" + profile])
        waitUntilProfileIsFree(profile: profile)
        return stale
    }

    /// `pgrep` の出力を PID の配列にする。
    public static func parsePIDs(_ output: String) -> [pid_t] {
        output
            .split(whereSeparator: { $0 == "\n" || $0 == " " })
            .compactMap { pid_t($0.trimmingCharacters(in: .whitespaces)) }
            .filter { $0 > 0 }
    }

    /// 落とした Chrome が消えるまで少し待つ。まだ生きているうちに次を起動すると、
    /// 新しいプロセスにならず古いインスタンスへ取り次がれてしまう。
    static func waitUntilProfileIsFree(profile: String, timeoutSeconds: Double = 5) {
        let deadline = Date(timeIntervalSinceNow: timeoutSeconds)
        while Date() < deadline {
            if parsePIDs(capture("/usr/bin/pgrep", ["-f", "--", "--user-data-dir=" + profile])).isEmpty { return }
            Thread.sleep(forTimeInterval: 0.2)
        }
        fputs("dedicated browser did not exit in time; the new window may reuse it\n", stderr)
    }

    /// 標準出力を受け取って外部コマンドを実行する。
    static func capture(_ launchPath: String, _ arguments: [String]) -> String {
        let task = Process()
        task.launchPath = launchPath
        task.arguments = arguments
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil else { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// 出力を捨てて外部コマンドを実行する。
    static func run(_ launchPath: String, _ arguments: [String]) {
        let task = Process()
        task.launchPath = launchPath
        task.arguments = arguments
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil else { return }
        task.waitUntilExit()
    }

    /// sh の単一引用符で囲む。
    static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
