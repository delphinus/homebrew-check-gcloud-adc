import Foundation

public enum GcloudReauth {
    /// 再認証で実行する zsh コマンド文字列を組み立てる。
    ///
    /// - ADC のみ (account == nil): 必要スコープ (calendar/drive 等) を明示して
    ///   ADC を設定する。素の login による scope 上書きを打ち消す。
    /// - 名前付きアカウント (account != nil): まず `gcloud auth login` で CLI の
    ///   アカウント資格情報を復旧し、続けて ADC を必要スコープ付きで設定する。
    ///   `gcloud auth login` は `--scopes` / `--update-adc` では calendar/drive を
    ///   付与できない (前者は scope 非対応、後者はデフォルトスコープで上書き) ため、
    ///   ADC は `application-default login --scopes=...` 側で明示的に設定する。
    public static func command(
        account: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        let adcLogin = "gcloud auth application-default login --scopes='\(Scopes.joined(environment))'"
        guard let account = account else { return adcLogin }
        let escaped = account.replacingOccurrences(of: "'", with: "'\\''")
        return "gcloud auth login '\(escaped)' && \(adcLogin)"
    }

    /// 再認証を実行する。
    ///
    /// 可能なら `Browser` の shim を噛ませ、専用プロファイルの Chrome ウィンドウで
    /// 認証させたうえで、gcloud の終了後にそのウィンドウを閉じる。後始末はコマンド
    /// 文字列の側に埋めてあるので、呼び出し側は Process の終了を待つだけでよい
    /// (`NotificationSystem.waitForReauth`)。
    ///
    /// 始める前に前回の再認証を落とすので、`open check-gcloud-adc://reauth` は
    /// 何度叩いても毎回まっさらなプロセスから始まる。
    static func run(account: String? = nil) -> Process? {
        let environment = ProcessInfo.processInfo.environment
        var script = command(account: account, environment: environment)
        if Browser.resolveExecutable(environment) != nil {
            Browser.terminateStaleSessions(profile: Browser.resolveProfile(environment))
        }
        if let session = Browser.makeSession(environment) {
            script = Browser.wrap(command: script, session: session)
        }
        let task = Process()
        task.launchPath = "/bin/zsh"
        task.arguments = ["-l", "-c", script]
        try? task.run()
        return task
    }
}
