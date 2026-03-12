import Foundation

enum GcloudReauth {
    static func run() -> Process? {
        let task = Process()
        task.launchPath = "/bin/zsh"
        task.arguments = ["-l", "-c", "gcloud auth login --update-adc"]
        try? task.run()
        return task
    }
}
