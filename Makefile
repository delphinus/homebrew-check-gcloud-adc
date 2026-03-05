BINARY_NAME := check-gcloud-adc
APP_BUNDLE := $(BINARY_NAME).app
APP_CONTENTS := $(APP_BUNDLE)/Contents
APP_MACOS := $(APP_CONTENTS)/MacOS

.PHONY: build build-universal clean

build:
	swiftc -emit-library -static -emit-module \
		-module-name Notification \
		-o libnotification.a notification.swift
	CGO_ENABLED=1 go build -o $(BINARY_NAME) .
	mkdir -p $(APP_MACOS)
	cp $(BINARY_NAME) $(APP_MACOS)/
	cp Info.plist $(APP_CONTENTS)/
	codesign --force --sign - --identifier com.delphinus.check-gcloud-adc $(APP_BUNDLE)

build-universal:
	# Build arm64
	swiftc -emit-library -static -emit-module \
		-module-name Notification \
		-target arm64-apple-macosx13.0 \
		-o libnotification.a notification.swift
	CGO_ENABLED=1 GOARCH=arm64 go build -o $(BINARY_NAME)-arm64 .
	# Build x86_64
	swiftc -emit-library -static -emit-module \
		-module-name Notification \
		-target x86_64-apple-macosx13.0 \
		-o libnotification.a notification.swift
	CGO_ENABLED=1 GOARCH=amd64 CC="clang -arch x86_64" \
		go build -o $(BINARY_NAME)-x86_64 .
	# Combine with lipo
	lipo -create -output $(BINARY_NAME) $(BINARY_NAME)-arm64 $(BINARY_NAME)-x86_64
	mkdir -p $(APP_MACOS)
	cp $(BINARY_NAME) $(APP_MACOS)/
	cp Info.plist $(APP_CONTENTS)/
	codesign --force --sign - --identifier com.delphinus.check-gcloud-adc $(APP_BUNDLE)

clean:
	rm -rf $(BINARY_NAME) $(BINARY_NAME)-arm64 $(BINARY_NAME)-x86_64 \
		$(APP_BUNDLE) libnotification.a Notification.swiftmodule
