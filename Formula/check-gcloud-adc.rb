class CheckGcloudAdc < Formula
  desc "Check Google Cloud ADC token validity and notify when expired"
  homepage "https://github.com/delphinus/homebrew-check-gcloud-adc"
  url "https://github.com/delphinus/homebrew-check-gcloud-adc/releases/download/v1.3.1/check-gcloud-adc.tar.gz"
  sha256 "6673d5c91e713ffa4bf5773b91125e6def10abd2000a52268ac64ad4311a77ff"
  version "1.3.1"

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
