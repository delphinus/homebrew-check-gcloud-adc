package main

import (
	"fmt"
	"os"
	"os/exec"
)

type notifier interface {
	send(title, message string, isTest bool)
}

type adcChecker interface {
	check() bool
}

type stateStore interface {
	isNotified() bool
	setNotified() error
	clearNotified()
}

type app struct {
	notifier   notifier
	adcChecker adcChecker
	state      stateStore
}

func (a *app) runTest() {
	a.notifier.send("Test Notification", "Notifications are working!", true)
	fmt.Println("Notification sent. Waiting for click... (Ctrl+C to cancel)")
	if waitForNotificationAction(120) {
		fmt.Println("Notification action handled.")
	} else {
		fmt.Println("Timed out waiting for notification click.")
	}
}

func (a *app) runReset() {
	a.state.clearNotified()
	fmt.Println("Cleared notification state.")
	fmt.Println("Opening System Settings > Notifications...")
	fmt.Println("Tip: Set the notification style to \"Alerts\" so notifications stay until clicked.")
	cmd := exec.Command("open", "x-apple.systempreferences:com.apple.Notifications-Settings")
	if err := cmd.Run(); err != nil {
		fmt.Fprintf(os.Stderr, "failed to open System Settings: %v\n", err)
		os.Exit(1)
	}
}

func (a *app) runCheck() {
	if a.adcChecker.check() {
		a.state.clearNotified()
		return
	}

	if a.state.isNotified() {
		return
	}

	a.notifier.send(
		"Google Cloud ADC Expired",
		"Click to re-authenticate with gcloud auth login --update-adc",
		false,
	)

	if err := a.state.setNotified(); err != nil {
		fmt.Fprintf(os.Stderr, "warning: failed to set notified flag: %v\n", err)
	}

	// Keep the process alive to handle the notification action when clicked.
	// The service interval is 300s, so wait up to 270s.
	waitForNotificationAction(270)
}
