package main

/*
#cgo CFLAGS: -x objective-c
#cgo LDFLAGS: -framework Foundation -framework AppKit -framework UserNotifications

#include <stdlib.h>
#include "notification.h"
*/
import "C"
import "unsafe"

func sendNotification(title, message string) {
	cTitle := C.CString(title)
	cMessage := C.CString(message)
	defer C.free(unsafe.Pointer(cTitle))
	defer C.free(unsafe.Pointer(cMessage))
	C.SendNotification(cTitle, cMessage)
}
