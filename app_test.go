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

type mockDeliveryChecker struct {
	delivered bool
}

func (d *mockDeliveryChecker) isDelivered() bool { return d.delivered }

type mockActionWaiter struct{}

func (w *mockActionWaiter) waitForAction(timeoutSeconds float64) bool { return false }

type mockStateStore struct {
	notified bool
	setErr   error
}

func (s *mockStateStore) isNotified() bool     { return s.notified }
func (s *mockStateStore) setNotified() error   { s.notified = true; return s.setErr }
func (s *mockStateStore) clearNotified()       { s.notified = false }

func newTestApp() (*app, *mockNotifier, *mockADCChecker, *mockDeliveryChecker, *mockStateStore) {
	n := &mockNotifier{}
	c := &mockADCChecker{}
	d := &mockDeliveryChecker{}
	s := &mockStateStore{}
	w := &mockActionWaiter{}
	return &app{notifier: n, adcChecker: c, deliveryChecker: d, actionWaiter: w, state: s}, n, c, d, s
}

func TestRunCheck_ADCValid_ClearsState(t *testing.T) {
	a, n, c, _, s := newTestApp()
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
	a, n, c, _, s := newTestApp()
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

func TestRunCheck_ADCInvalid_AlreadyNotified_StillDelivered_DoesNothing(t *testing.T) {
	a, n, c, d, s := newTestApp()
	c.valid = false
	s.notified = true
	d.delivered = true

	a.runCheck()

	if len(n.calls) != 0 {
		t.Error("expected no notification to be sent")
	}
	if !s.notified {
		t.Error("expected notified state to remain set")
	}
}

func TestRunCheck_ADCInvalid_AlreadyNotified_NotDelivered_ResendsNotification(t *testing.T) {
	a, n, c, d, s := newTestApp()
	c.valid = false
	s.notified = true
	d.delivered = false

	a.runCheck()

	if len(n.calls) != 1 {
		t.Fatalf("expected 1 notification, got %d", len(n.calls))
	}
	if n.calls[0].title != "Google Cloud ADC Expired" {
		t.Errorf("unexpected title: %s", n.calls[0].title)
	}
	if !s.notified {
		t.Error("expected notified state to remain set")
	}
}

func TestRunTest_SendsTestNotification(t *testing.T) {
	a, n, _, _, _ := newTestApp()

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
