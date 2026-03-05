BINARY_NAME := check-gcloud-adc
APP_BUNDLE := $(BINARY_NAME).app
APP_CONTENTS := $(APP_BUNDLE)/Contents
APP_MACOS := $(APP_CONTENTS)/MacOS

.PHONY: build clean

build: libnotification.a
	CGO_ENABLED=1 go build -o $(BINARY_NAME) .
	mkdir -p $(APP_MACOS)
	cp $(BINARY_NAME) $(APP_MACOS)/
	cp Info.plist $(APP_CONTENTS)/
	codesign --force --sign - --identifier com.delphinus.check-gcloud-adc $(APP_BUNDLE)

libnotification.a: notification.swift
	swiftc -emit-library -static -emit-module \
		-module-name Notification \
		-o $@ $<

clean:
	rm -rf $(BINARY_NAME) $(APP_BUNDLE) libnotification.a Notification.swiftmodule
