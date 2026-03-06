package main

/*
#cgo LDFLAGS: -L${SRCDIR} -lnotification -framework Foundation -framework AppKit -framework UserNotifications
#include <stdlib.h>
#include "notification.h"
*/
import "C"
import "unsafe"

func sendNotification(title, message string, isTest bool) {
	cTitle := C.CString(title)
	cMessage := C.CString(message)
	defer C.free(unsafe.Pointer(cTitle))
	defer C.free(unsafe.Pointer(cMessage))
	var cIsTest C.int
	if isTest {
		cIsTest = 1
	}
	C.SendNotification(cTitle, cMessage, cIsTest)
}

func handlePendingActions() bool {
	return C.HandlePendingActions() != 0
}
