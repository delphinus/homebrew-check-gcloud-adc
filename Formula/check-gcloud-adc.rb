class CheckGcloudAdc < Formula
  desc "Check Google Cloud ADC token validity and notify when expired"
  homepage "https://github.com/delphinus/homebrew-check-gcloud-adc"
  url "https://github.com/delphinus/homebrew-check-gcloud-adc/releases/download/v2.0.0/check-gcloud-adc.tar.gz"
  sha256 "13cc4c580ac0b84966dbd55b68603e85b26d44e6a32a9e53f86ed9e71a190c05"
  version "2.0.0"

  depends_on :macos

  def install
    prefix.install "check-gcloud-adc.app"
    bin.write_exec_script prefix/"check-gcloud-adc.app/Contents/MacOS/check-gcloud-adc"
  end

  def post_install
    system "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister",
 "-R", prefix/"check-gcloud-adc.app"
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
    assert_match "Check Google Cloud ADC token validity", shell_output("\#{bin}/check-gcloud-adc --help")
  end
end
