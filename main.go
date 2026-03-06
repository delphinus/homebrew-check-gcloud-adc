package main

import (
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
)

type macNotifier struct{}

func (n *macNotifier) send(title, message string, isTest bool) {
	sendNotification(title, message, isTest)
}

type gcloudADCChecker struct{}

func (c *gcloudADCChecker) check() bool {
	cmd := exec.Command("gcloud", "auth", "application-default", "print-access-token", "--quiet")
	cmd.Stdout = nil
	cmd.Stderr = nil
	return cmd.Run() == nil
}

type fileStateStore struct {
	dir string
}

func newFileStateStore() *fileStateStore {
	cacheDir, err := os.UserCacheDir()
	if err != nil {
		cacheDir = filepath.Join(os.Getenv("HOME"), ".cache")
	}
	return &fileStateStore{dir: filepath.Join(cacheDir, "check-gcloud-adc")}
}

func (s *fileStateStore) flagFile() string {
	return filepath.Join(s.dir, "notified")
}

func (s *fileStateStore) isNotified() bool {
	_, err := os.Stat(s.flagFile())
	return err == nil
}

func (s *fileStateStore) setNotified() error {
	if err := os.MkdirAll(s.dir, 0o755); err != nil {
		return err
	}
	return os.WriteFile(s.flagFile(), []byte{}, 0o644)
}

func (s *fileStateStore) clearNotified() {
	os.Remove(s.flagFile())
}

func main() {
	// Handle pending notification responses or URL scheme events from previous runs
	if handlePendingActions() {
		return
	}

	help := flag.Bool("help", false, "show help")
	test := flag.Bool("test", false, "send a test notification (skips ADC check)")
	reset := flag.Bool("reset", false, "open notification settings and clear state")
	flag.Parse()

	if *help {
		fmt.Println("check-gcloud-adc: Check Google Cloud ADC token validity")
		fmt.Println()
		fmt.Println("If the ADC token is expired or invalid, a macOS notification is sent.")
		fmt.Println("Clicking the notification opens a WezTerm tab to re-authenticate.")
		fmt.Println()
		fmt.Println("You can also trigger actions via URL scheme:")
		fmt.Println("  open check-gcloud-adc://reauth      re-authenticate")
		fmt.Println("  open check-gcloud-adc://open-repo    open the repository")
		fmt.Println()
		fmt.Println("Flags:")
		fmt.Println("  --help   show this help message")
		fmt.Println("  --test   send a test notification (skips ADC check)")
		fmt.Println("  --reset  open notification settings and clear state")
		os.Exit(0)
	}

	a := &app{
		notifier:   &macNotifier{},
		adcChecker: &gcloudADCChecker{},
		state:      newFileStateStore(),
	}

	if *reset {
		a.runReset()
		return
	}

	if *test {
		a.runTest()
		return
	}

	a.runCheck()
}
