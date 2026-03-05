class CheckGcloudAdc < Formula
  desc "Check Google Cloud ADC token validity and notify when expired"
  homepage "https://github.com/delphinus/homebrew-check-gcloud-adc"
  url "https://github.com/delphinus/homebrew-check-gcloud-adc/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "4a5542a5a888b2486207887649fb38b43c2ca0d4d958ac9a8326780d26377d75"
  version "1.0.0"
  head "https://github.com/delphinus/homebrew-check-gcloud-adc.git", branch: "main"

  depends_on "go" => :build
  depends_on :macos

  def install
    ENV["CGO_ENABLED"] = "1"
    system "go", "build",
      "-ldflags", "-extldflags '-sectcreate __TEXT __info_plist #{buildpath}/Info.plist'",
      "-o", bin/"check-gcloud-adc", "."
  end

  service do
    run opt_bin/"check-gcloud-adc"
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
