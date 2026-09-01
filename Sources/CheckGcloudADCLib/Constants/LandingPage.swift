import Foundation

/// gcloud がローカルのコールバックで返す完了ページ (`oauth2_landing.html`) から、
/// `cloud.google.com` へのリダイレクトを外す。
///
/// 素の gcloud は認可コードを受け取ると、この HTML の meta refresh と
/// `window.location.href` の 2 つで `https://cloud.google.com/sdk/auth_success`
/// へ飛ばす。VPN のような共有 IP から出ていると、その先に Google の bot チェック
/// (`/sorry/index` の CAPTCHA) が挟まる。認証はコードを受け取った時点で既に
/// 済んでいるのに最後の画面へ辿り着けず、`Browser` は gcloud の終了直後に
/// ウィンドウを閉じるので、利用者には「CAPTCHA が出た瞬間に窓が消えた」ように
/// 見える。`Browser.closeGraceSeconds` はリダイレクトを取りこぼさないための
/// 猶予であって、人間が CAPTCHA を解く時間ではない。
///
/// リダイレクトを外すと、同じファイルに入っている静的な完了ページ
/// (「You are now authenticated with the Google Cloud SDK.」) がそのまま最後の
/// 画面になる。gcloud はこのレスポンスの中身を読まない (`flow.py` は本文を返す
/// 前に認可コードを確定させている) ので、認証の挙動は変わらない。
///
/// SDK は Homebrew や `gcloud components update` の管理下にあり、更新のたびに
/// 元へ戻る。そのため再認証のたびに冪等に当て直す。
public enum LandingPage {
    /// 空文字を設定すると書き換えを行わない (素の gcloud の挙動に戻る)。
    public static let envKey = "CHECK_GCLOUD_ADC_LANDING_PAGE"

    /// SDK の場所の上書き。空なら PATH 上の `gcloud` から辿る。
    public static let sdkRootEnvKey = "CHECK_GCLOUD_ADC_SDK_ROOT"

    /// SDK ルートから見た完了ページの位置。
    public static let relativePath = "lib/googlecloudsdk/core/credentials/oauth2_landing.html"

    /// 書き換えたあとに残っていなければならない目印。リダイレクトを外すと
    /// これを含む静的なページが表に出る。将来 Google がこの中身を変えて目印が
    /// 消えていたら、真っ白な画面を作らないよう書き換えを見送る。
    public static let fallbackMarker = "You are now authenticated"

    /// 書き換えが有効か。
    public static func isEnabled(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        guard let raw = environment[envKey] else { return true }
        return !raw.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// `<sdk_root>/bin/gcloud` から SDK ルートを求める。`bin/` の下に無ければ nil。
    public static func sdkRoot(fromExecutable executable: String) -> String? {
        let bin = (executable as NSString).deletingLastPathComponent
        guard (bin as NSString).lastPathComponent == "bin" else { return nil }
        let root = (bin as NSString).deletingLastPathComponent
        return root.isEmpty || root == "/" ? nil : root
    }

    /// SDK ルートの下の完了ページのパス。
    public static func page(inSDKRoot root: String) -> String {
        (root as NSString).appendingPathComponent(relativePath)
    }

    /// 完了ページの候補を優先順に返す。
    ///
    /// `gcloud` は symlink 越しに置かれていることが多い (Homebrew の cask なら
    /// `/opt/homebrew/bin/gcloud` → Caskroom → `share/google-cloud-sdk`)。実体側と
    /// symlink 側で SDK ルートの見え方が変わるので、両方を候補に挙げて実在する
    /// ほうを使う。
    public static func candidates(
        _ environment: [String: String] = [:],
        executable: String?
    ) -> [String] {
        var roots: [String] = []
        if let raw = environment[sdkRootEnvKey] {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { roots.append(trimmed) }
        }
        if let executable = executable {
            let resolved = (executable as NSString).resolvingSymlinksInPath
            for path in [resolved, executable] {
                if let root = sdkRoot(fromExecutable: path), !roots.contains(root) {
                    roots.append(root)
                }
            }
        }
        return roots.map(page(inSDKRoot:))
    }

    /// リダイレクトを外した HTML を返す。既に外れている・目印が見当たらない
    /// 場合は nil (= 何もしない)。
    public static func redirectRemoved(from html: String) -> String? {
        // 行ごと消す。あとに空行が残ってもページの見た目は変わらない。
        let patterns = [
            // <meta http-equiv="refresh" content="0;url=https://cloud.google.com/sdk/auth_success">
            #"[ \t]*<meta[^>]+http-equiv=["']?refresh["']?[^>]*>[ \t]*\n?"#,
            // <script ...>...window.location.href = "..."...</script>
            // 別の <script> を巻き込まないよう、中身は閉じタグの手前までに限る。
            #"[ \t]*<script\b[^>]*>(?:(?!</script>)[\s\S])*window\.location(?:(?!</script>)[\s\S])*</script>[ \t]*\n?"#,
        ]
        var patched = html
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            patched = regex.stringByReplacingMatches(
                in: patched,
                range: NSRange(patched.startIndex..., in: patched),
                withTemplate: ""
            )
        }
        guard patched != html else { return nil }
        guard patched.contains(fallbackMarker) else { return nil }
        return patched
    }

    /// 完了ページを書き換える。
    ///
    /// 見つからない・既に当たっている・書けない、のいずれでも黙って false を
    /// 返すだけにしてある。ここで失敗しても再認証そのものは成立するので、
    /// 止めるほどのことではない。
    ///
    /// - Returns: 実際に書き換えたら true。
    @discardableResult
    public static func apply(
        _ environment: [String: String] = ProcessInfo.processInfo.environment,
        locate: () -> String? = { locateGcloud() }
    ) -> Bool {
        guard isEnabled(environment) else { return false }
        let fm = FileManager.default
        let paths = candidates(environment, executable: locate())
        guard let path = paths.first(where: { fm.fileExists(atPath: $0) }) else { return false }
        guard let html = try? String(contentsOfFile: path, encoding: .utf8) else { return false }
        guard let patched = redirectRemoved(from: html) else { return false }

        // atomically な書き出しは元のファイルを置き換えるので、パーミッションを
        // 引き継がせる。
        let permissions = (try? fm.attributesOfItem(atPath: path))?[.posixPermissions]
        do {
            try patched.write(toFile: path, atomically: true, encoding: .utf8)
            if let permissions = permissions {
                try? fm.setAttributes([.posixPermissions: permissions], ofItemAtPath: path)
            }
        } catch {
            fputs("could not drop the auth_success redirect (\(path)): \(error.localizedDescription)\n", stderr)
            return false
        }
        return true
    }

    /// PATH 上の `gcloud` を探す。
    public static func locateGcloud() -> String? {
        let found = Browser.capture("/usr/bin/which", ["gcloud"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return found.isEmpty ? nil : found
    }
}
