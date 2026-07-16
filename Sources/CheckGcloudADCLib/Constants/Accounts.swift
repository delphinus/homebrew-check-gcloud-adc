import Foundation

/// トークンチェック対象アカウントの許可リスト (allowlist) 定義。
///
/// 既定 (未設定) では `gcloud auth list` の全アカウントをチェックする。
/// 許可リストが指定された場合は、そこに含まれるアカウントだけをチェックする。
/// ADC (application-default) のチェックは許可リストと無関係に常に行う。
///
/// 解決順:
/// 1. 環境変数 `CHECK_GCLOUD_ADC_ACCOUNTS` (カンマ / 空白区切り) があればそれを使う。
/// 2. 無ければ設定ファイル `${XDG_CONFIG_HOME:-~/.config}/check-gcloud-adc/accounts`
///    (1 行 1 アカウント、`#` 以降はコメント) を読む。
/// 3. どちらも無ければ空 = フィルタ無し (全アカウント)。
public enum Accounts {
    public static let envKey = "CHECK_GCLOUD_ADC_ACCOUNTS"

    /// 環境変数値をパースする (カンマ / 空白区切り)。
    static func parseEnv(_ raw: String) -> [String] {
        raw
            .split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// 設定ファイル本文をパースする (1 行 1 アカウント、`#` 以降コメント、空行無視)。
    static func parseFile(_ text: String) -> [String] {
        text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                let withoutComment = line.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
                return withoutComment.trimmingCharacters(in: .whitespaces)
            }
            .filter { !$0.isEmpty }
    }

    /// 設定ファイルのパスを返す (`$XDG_CONFIG_HOME` があれば優先、無ければ `~/.config`)。
    public static func defaultConfigPath(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        let base: String
        if let xdg = environment["XDG_CONFIG_HOME"], !xdg.isEmpty {
            base = xdg
        } else {
            let home = environment["HOME"] ?? NSHomeDirectory()
            base = (home as NSString).appendingPathComponent(".config")
        }
        return (base as NSString).appendingPathComponent("check-gcloud-adc/accounts")
    }

    /// 環境変数と設定ファイル本文から許可リストを解決する (env 優先)。
    /// 空配列はフィルタ無しを意味する。テスト用に副作用のない形で切り出す。
    public static func allowlist(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        configText: String? = nil
    ) -> [String] {
        if let raw = environment[envKey] {
            let parsed = parseEnv(raw)
            if !parsed.isEmpty { return parsed }
        }
        if let text = configText {
            return parseFile(text)
        }
        return []
    }

    /// 本番用: 環境変数を見つつ設定ファイルを読み込んで許可リストを解決する。
    public static func resolveAllowlist(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String] {
        // env が有効ならファイル I/O 不要。
        if let raw = environment[envKey], !parseEnv(raw).isEmpty {
            return parseEnv(raw)
        }
        let path = defaultConfigPath(environment)
        let text = try? String(contentsOfFile: path, encoding: .utf8)
        return allowlist(environment: environment, configText: text)
    }

    /// 許可リストでアカウントを絞る。許可リストが空ならそのまま返す (フィルタ無し)。
    public static func filter(_ accounts: [String], allowlist: [String]) -> [String] {
        guard !allowlist.isEmpty else { return accounts }
        let allow = Set(allowlist)
        return accounts.filter { allow.contains($0) }
    }
}
