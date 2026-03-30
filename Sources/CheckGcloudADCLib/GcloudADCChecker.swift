import Foundation

public final class GcloudADCChecker {
    public init() {}
}

// MARK: - ADCChecker

extension GcloudADCChecker: ADCChecker {
    public func checkAll() -> [String] {
        var expired: [String] = []

        // Check Application Default Credentials (global, not per-account)
        if !checkADC() {
            expired.append("application-default")
        }

        // Check per-account auth tokens
        let accounts = listAccounts()
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

    func checkADC() -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = ["gcloud", "auth", "application-default", "print-access-token", "--quiet"]
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
