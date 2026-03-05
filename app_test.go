package main

import "testing"

type mockNotifier struct {
	calls []notifyCall
}

type notifyCall struct {
	title   string
	message string
	isTest  bool
}

func (n *mockNotifier) send(title, message string, isTest bool) {
	n.calls = append(n.calls, notifyCall{title, message, isTest})
}

type mockADCChecker struct {
	valid bool
}

func (c *mockADCChecker) check() bool {
	return c.valid
}

type mockStateStore struct {
	notified bool
	setErr   error
}

func (s *mockStateStore) isNotified() bool     { return s.notified }
func (s *mockStateStore) setNotified() error   { s.notified = true; return s.setErr }
func (s *mockStateStore) clearNotified()       { s.notified = false }

func newTestApp() (*app, *mockNotifier, *mockADCChecker, *mockStateStore) {
	n := &mockNotifier{}
	c := &mockADCChecker{}
	s := &mockStateStore{}
	return &app{notifier: n, adcChecker: c, state: s}, n, c, s
}

func TestRunCheck_ADCValid_ClearsState(t *testing.T) {
	a, n, c, s := newTestApp()
	c.valid = true
	s.notified = true

	a.runCheck()

	if s.notified {
		t.Error("expected notified state to be cleared")
	}
	if len(n.calls) != 0 {
		t.Error("expected no notification to be sent")
	}
}

func TestRunCheck_ADCInvalid_NotYetNotified_SendsNotification(t *testing.T) {
	a, n, c, s := newTestApp()
	c.valid = false
	s.notified = false

	a.runCheck()

	if len(n.calls) != 1 {
		t.Fatalf("expected 1 notification, got %d", len(n.calls))
	}
	if n.calls[0].title != "Google Cloud ADC Expired" {
		t.Errorf("unexpected title: %s", n.calls[0].title)
	}
	if n.calls[0].isTest {
		t.Error("expected isTest to be false")
	}
	if !s.notified {
		t.Error("expected notified state to be set")
	}
}

func TestRunCheck_ADCInvalid_AlreadyNotified_DoesNothing(t *testing.T) {
	a, n, c, s := newTestApp()
	c.valid = false
	s.notified = true

	a.runCheck()

	if len(n.calls) != 0 {
		t.Error("expected no notification to be sent")
	}
	if !s.notified {
		t.Error("expected notified state to remain set")
	}
}

func TestRunTest_SendsTestNotification(t *testing.T) {
	a, n, _, _ := newTestApp()

	a.runTest()

	if len(n.calls) != 1 {
		t.Fatalf("expected 1 notification, got %d", len(n.calls))
	}
	if n.calls[0].title != "Test Notification" {
		t.Errorf("unexpected title: %s", n.calls[0].title)
	}
	if !n.calls[0].isTest {
		t.Error("expected isTest to be true")
	}
}
