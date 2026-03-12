import Foundation

public protocol ADCChecker {
    func check() -> Bool
}

public final class GcloudADCChecker {
    public init() {}
}

// MARK: - ADCChecker

extension GcloudADCChecker: ADCChecker {
    public func check() -> Bool {
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
}
