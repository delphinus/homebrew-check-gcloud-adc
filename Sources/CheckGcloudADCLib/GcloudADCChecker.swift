import Foundation

public final class GcloudADCChecker {
    public init() {}
}

// MARK: - ADCChecker

extension GcloudADCChecker: ADCChecker {
    public func checkAll() -> [String] {
        let adcExpired = !checkADC()

        // Check per-account auth tokens.
        // 許可リスト (CHECK_GCLOUD_ADC_ACCOUNTS or 設定ファイル) が指定されて
        // いれば、そこに含まれるアカウントだけをチェックする。未指定なら全件。
        var expired: [String] = []
        let accounts = Accounts.filter(listAccounts(), allowlist: Accounts.resolveAllowlist())
        for account in accounts {
            if !checkToken(account: account) {
                expired.append(account)
            }
        }

        // ADC の通知はアカウントが全て有効な場合のみ出す。アカウント再認証は
        // 後段で ADC を必要スコープ付きで設定し直すので、ADC の期限・スコープも
        // そこで併せて復旧する。取りこぼしがあっても次回チェックで adcExpired
        // として拾い直し、専用通知を出す。
        if adcExpired && expired.isEmpty {
            expired.append("application-default")
        }

        return expired
    }
}

// MARK: - Privates

private extension GcloudADCChecker {
    func listAccounts() -> [String] {
        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = ["gcloud", "auth", "list", "--format=json(account)"]
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()
            guard task.terminationStatus == 0 else { return [] }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }

            return json.compactMap { $0["account"] as? String }
        } catch {
            return []
        }
    }

    /// ADC が「有効」かを判定する。トークンが発行でき、かつ必要スコープを
    /// すべて含んでいるときのみ true。スコープ不足 (= 他の gcloud login に
    /// 上書きされて calendar/drive 等が抜けた状態) も無効として扱う。
    func checkADC() -> Bool {
        guard let token = adcAccessToken() else { return false }
        return tokenHasRequiredScopes(token)
    }

    /// ADC からアクセストークンを取得する (失敗時は nil)。
    func adcAccessToken() -> String? {
        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = ["gcloud", "auth", "application-default", "print-access-token", "--quiet"]
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
            guard task.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let token = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (token?.isEmpty == false) ? token : nil
        } catch {
            return nil
        }
    }

    /// tokeninfo で当該トークンのスコープを取得し、必要スコープを
    /// すべて含むかを判定する。ネットワーク不通など判定不能時は、
    /// 誤検知 (無用な再認証通知) を避けるため true を返す。
    func tokenHasRequiredScopes(_ token: String) -> Bool {
        let required = Scopes.requiredForCheck()
        if required.isEmpty { return true }

        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = [
            "curl", "-s", "--max-time", "10",
            "https://oauth2.googleapis.com/tokeninfo?access_token=\(token)",
        ]
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
            guard task.terminationStatus == 0 else { return true }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return true
            }
            // tokeninfo がエラーを返した = トークン自体が無効。
            if json["error"] != nil || json["error_description"] != nil { return false }
            let scopeStr = (json["scope"] as? String) ?? ""
            let granted = Set(scopeStr.split(separator: " ").map(String.init))
            return required.allSatisfy { granted.contains($0) }
        } catch {
            return true
        }
    }

    func checkToken(account: String) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = ["gcloud", "auth", "print-access-token", "--quiet", "--account=\(account)"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }
}
