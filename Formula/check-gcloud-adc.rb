class CheckGcloudAdc < Formula
  desc "Check Google Cloud ADC token validity and notify when expired"
  homepage "https://github.com/delphinus/homebrew-check-gcloud-adc"
  url "https://github.com/delphinus/homebrew-check-gcloud-adc/archive/refs/tags/v1.0.2.tar.gz"
  sha256 "d31cc2a237a905a811d4baf4ad03229e4f8b002e166ed955f0b274c62ddedd39"
  version "1.0.2"
  head "https://github.com/delphinus/homebrew-check-gcloud-adc.git", branch: "main"

  depends_on "go" => :build
  depends_on :macos

  def install
    system "swiftc", "-emit-library", "-static", "-emit-module",
           "-module-name", "Notification",
           "-o", "libnotification.a", "notification.swift"
    ENV["CGO_ENABLED"] = "1"
    system "go", "build", "-o", "check-gcloud-adc", "."

    app = prefix/"check-gcloud-adc.app/Contents"
    (app/"MacOS").install "check-gcloud-adc"
    app.install "Info.plist"

    system "codesign", "--force", "--sign", "-",
 "--identifier", "com.delphinus.check-gcloud-adc",
 prefix/"check-gcloud-adc.app"

    bin.write_exec_script app/"MacOS/check-gcloud-adc"
  end

  service do
    run opt_prefix/"check-gcloud-adc.app/Contents/MacOS/check-gcloud-adc"
    run_type :interval
    interval 300
    environment_variables PATH: "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    log_path var/"log/check-gcloud-adc/output.log"
    error_log_path var/"log/check-gcloud-adc/error.log"
  end

  test do
    assert_match "Check Google Cloud ADC token validity", shell_output("#{bin}/check-gcloud-adc --help")
  end
end
