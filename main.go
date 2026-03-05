package main

import (
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
)

func flagDir() string {
	cacheDir, err := os.UserCacheDir()
	if err != nil {
		cacheDir = filepath.Join(os.Getenv("HOME"), ".cache")
	}
	return filepath.Join(cacheDir, "check-gcloud-adc")
}

func flagFile() string {
	return filepath.Join(flagDir(), "notified")
}

func isNotified() bool {
	_, err := os.Stat(flagFile())
	return err == nil
}

func setNotified() error {
	if err := os.MkdirAll(flagDir(), 0o755); err != nil {
		return err
	}
	return os.WriteFile(flagFile(), []byte{}, 0o644)
}

func clearNotified() {
	os.Remove(flagFile())
}

func checkADC() bool {
	cmd := exec.Command("gcloud", "auth", "application-default", "print-access-token", "--quiet")
	cmd.Stdout = nil
	cmd.Stderr = nil
	return cmd.Run() == nil
}

func main() {
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
		fmt.Println("Flags:")
		fmt.Println("  --help   show this help message")
		fmt.Println("  --test   send a test notification (skips ADC check)")
		fmt.Println("  --reset  open notification settings and clear state")
		os.Exit(0)
	}

	if *reset {
		clearNotified()
		fmt.Println("Cleared notification state.")
		fmt.Println("Opening System Settings > Notifications...")
		fmt.Println("Tip: Set the notification style to \"Alerts\" so notifications stay until clicked.")
		cmd := exec.Command("open", "x-apple.systempreferences:com.apple.Notifications-Settings")
		if err := cmd.Run(); err != nil {
			fmt.Fprintf(os.Stderr, "failed to open System Settings: %v\n", err)
			os.Exit(1)
		}
		return
	}

	if *test {
		sendNotification("Test Notification", "Notifications are working!", true)
		return
	}

	if checkADC() {
		clearNotified()
		return
	}

	// ADC is invalid
	if isNotified() {
		return
	}

	sendNotification(
		"Google Cloud ADC Expired",
		"Click to re-authenticate with gcloud auth login --update-adc",
		false,
	)

	if err := setNotified(); err != nil {
		fmt.Fprintf(os.Stderr, "warning: failed to set notified flag: %v\n", err)
	}
}
