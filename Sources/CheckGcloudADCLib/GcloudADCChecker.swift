import Foundation

public final class GcloudADCChecker {
    public init() {}
}

// MARK: - ADCChecker

extension GcloudADCChecker: ADCChecker {
    public func checkAll() -> [String] {
        let accounts = listAccounts()
        if accounts.isEmpty {
            // Fallback: single ADC check
            if !checkToken(account: nil) {
                return ["default"]
            }
            return []
        }

        var expired: [String] = []
        for account in accounts {
            if !checkToken(account: account) {
                expired.append(account)
            }
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

    func checkToken(account: String?) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        var args = ["gcloud", "auth", "print-access-token", "--quiet"]
        if let account = account {
            args.append("--account=\(account)")
        }
        task.arguments = args
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
