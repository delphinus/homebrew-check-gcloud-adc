class CheckGcloudAdc < Formula
  desc "Check Google Cloud ADC token validity and notify when expired"
  homepage "https://github.com/delphinus/homebrew-check-gcloud-adc"
  url "https://github.com/delphinus/homebrew-check-gcloud-adc/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "e1d3e5f30174bf347acc23e17257518ed581bb177a3db27ffe7e0fb39db05a1d"
  version "0.1.0"
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
