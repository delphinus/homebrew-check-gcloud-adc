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
        exit 0
        """
    }

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
    /// 後始末は EXIT トラップに載せる。gcloud が途中で落ちても、こちらが
    /// 終了させられても専用ウィンドウが残らない。zsh の EXIT トラップは終了
    /// ステータスを書き換えないので、gcloud の終了コードはそのまま返る。
    public static func wrap(command: String, session: Session) -> String {
        let shim = quote(session.shimDir)
        let opener = quote((session.shimDir as NSString).appendingPathComponent("open-url"))
        let pattern = quote("--user-data-dir=" + session.profile)
        let cleanup = [
            "sleep \(closeGraceSeconds)",
            "/usr/bin/pkill -TERM -f -- \(pattern) > /dev/null 2>&1",
            "/bin/rm -rf \(shim)",
        ].joined(separator: "; ")
        return [
            "export BROWSER=\(opener)",
            "export PATH=\(shim):\"$PATH\"",
            "\(cleanupFunction)() { \(cleanup); }",
            "trap \(cleanupFunction) EXIT INT TERM",
            command,
        ].joined(separator: "; ")
    }

    /// 後始末用シェル関数の名前。ユーザの rc と衝突しないように前置きを付ける。
    static let cleanupFunction = "__check_gcloud_adc_close_browser"

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
            .appendingPathComponent("check-gcloud-adc-browser-\(UUID().uuidString)")
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

    /// sh の単一引用符で囲む。
    static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
