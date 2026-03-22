import Foundation

enum GcloudReauth {
    static func run(account: String? = nil) -> Process? {
        let task = Process()
        task.launchPath = "/bin/zsh"
        var cmd = "gcloud auth login --update-adc"
        if let account = account {
            let escaped = account.replacingOccurrences(of: "'", with: "'\\''")
            cmd += " '\(escaped)'"
        }
        task.arguments = ["-l", "-c", cmd]
        try? task.run()
        return task
    }
}
