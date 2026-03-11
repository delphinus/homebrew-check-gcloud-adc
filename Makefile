BINARY_NAME := check-gcloud-adc
APP_BUNDLE := $(BINARY_NAME).app
APP_CONTENTS := $(APP_BUNDLE)/Contents
APP_MACOS := $(APP_CONTENTS)/MacOS
APP_RESOURCES := $(APP_CONTENTS)/Resources

.PHONY: build build-universal test clean

build:
	swift build -c release
	swift generate_icon.swift
	iconutil -c icns AppIcon.iconset -o AppIcon.icns
	mkdir -p $(APP_MACOS) $(APP_RESOURCES)
	cp $$(swift build -c release --show-bin-path)/$(BINARY_NAME) $(APP_MACOS)/
	cp Info.plist $(APP_CONTENTS)/
	cp AppIcon.icns $(APP_RESOURCES)/
	codesign --force --sign - --identifier com.delphinus.check-gcloud-adc $(APP_BUNDLE)

build-universal:
	swift build -c release --arch arm64 --arch x86_64
	swift generate_icon.swift
	iconutil -c icns AppIcon.iconset -o AppIcon.icns
	mkdir -p $(APP_MACOS) $(APP_RESOURCES)
	cp $$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/$(BINARY_NAME) $(APP_MACOS)/
	cp Info.plist $(APP_CONTENTS)/
	cp AppIcon.icns $(APP_RESOURCES)/
	codesign --force --sign - --identifier com.delphinus.check-gcloud-adc $(APP_BUNDLE)

test:
	swift run check-gcloud-adc-tests

clean:
	swift package clean
	rm -rf $(APP_BUNDLE) AppIcon.iconset AppIcon.icns
