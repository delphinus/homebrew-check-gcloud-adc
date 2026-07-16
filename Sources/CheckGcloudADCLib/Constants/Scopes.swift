import Foundation

/// ADC に持たせるべき OAuth スコープの定義。
///
/// 既定では meet-notes 等が必要とする calendar / drive を含む superset を使う。
/// `CHECK_GCLOUD_ADC_SCOPES` 環境変数 (カンマ / 空白区切り) で上書きできる。
public enum Scopes {
    public static let envKey = "CHECK_GCLOUD_ADC_SCOPES"

    /// 既定スコープ。`gcloud auth application-default login` の既定に
    /// calendar.readonly / drive.readonly / drive.file を足した superset。
    /// - calendar.readonly / drive.readonly: meet-notes 等の議事録取得に必要。
    /// - drive.file: ツールが作成した Google Sheets 等のファイルを作成・編集するため
    ///   (アプリが作成したファイルのみに限定される最小権限。既存の任意ファイルは触れない)。
    public static let defaultScopes: [String] = [
        "openid",
        "https://www.googleapis.com/auth/userinfo.email",
        "https://www.googleapis.com/auth/cloud-platform",
        "https://www.googleapis.com/auth/calendar.readonly",
        "https://www.googleapis.com/auth/drive.readonly",
        "https://www.googleapis.com/auth/drive.file",
    ]

    /// 環境変数があればそれを、無ければ既定を返す。
    public static func resolve(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String] {
        if let raw = environment[envKey] {
            let parsed = raw
                .split(whereSeparator: { $0 == "," || $0 == " " })
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            if !parsed.isEmpty { return parsed }
        }
        return defaultScopes
    }

    /// アクセストークンの検証に使うスコープ。
    /// tokeninfo の `scope` には "openid" が含まれないため除外する。
    public static func requiredForCheck(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String] {
        resolve(environment).filter { $0 != "openid" }
    }

    /// `--scopes=` にそのまま渡せるカンマ区切り文字列。
    public static func joined(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        resolve(environment).joined(separator: ",")
    }
}
