import Foundation

enum GcloudReauth {
    static func run(account: String? = nil) -> Process? {
        let task = Process()
        task.launchPath = "/bin/zsh"
        let cmd: String
        if let account = account {
            // 名前付きアカウントの再認証。--update-adc で ADC も併せて更新する。
            let escaped = account.replacingOccurrences(of: "'", with: "'\\''")
            cmd = "gcloud auth login --update-adc '\(escaped)'"
        } else {
            // ADC の再認証。必要スコープ (calendar/drive 等) を常に付与し、
            // 素の login による scope 上書きを打ち消す。
            cmd = "gcloud auth application-default login --scopes='\(Scopes.joined())'"
        }
        task.arguments = ["-l", "-c", cmd]
        try? task.run()
        return task
    }
}
