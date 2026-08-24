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
/// - プロファイルのディレクトリ自体は残すので、Google のログインセッションは
///   次回の再認証に引き継がれる (= プロファイルが固定される)。
/// - gcloud が終わったら、その `--user-data-dir` を持つプロセスだけを終了させる。
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

    /// 既定の実行ファイル。
    public static let defaultExecutable = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

    /// gcloud 終了後、ウィンドウを閉じるまでの猶予 (秒)。最後のリダイレクトを
    /// 取りこぼさないための保険。
    public static let closeGraceSeconds = 1

    /// 書き出した shim の場所と、使うプロファイルの組。
    public struct Session {
        public let shimDir: String
        public let profile: String

        public init(shimDir: String, profile: String) {
            self.shimDir = shimDir
            self.profile = profile
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

    /// shim スクリプトの中身。
    public static func shimScript(executable: String, profile: String) -> String {
        """
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
          --new-window "$url" > /dev/null 2>&1 &
        exit 0
        """
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
            try shimScript(executable: executable, profile: profile)
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

        return Session(shimDir: shimDir, profile: profile)
    }

    /// sh の単一引用符で囲む。
    static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
