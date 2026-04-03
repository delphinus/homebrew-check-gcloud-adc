BINARY_NAME := check-gcloud-adc
APP_BUNDLE := $(BINARY_NAME).app
DERIVED_DATA := .build/DerivedData

.PHONY: generate build build-universal test clean

generate:
	swift generate_icon.swift
	iconutil -c icns AppIcon.iconset -o AppIcon.icns
	xcodegen generate

build: generate
	xcodebuild -project $(BINARY_NAME).xcodeproj -scheme $(BINARY_NAME) -configuration Release -derivedDataPath $(DERIVED_DATA) build
	cp -R $(DERIVED_DATA)/Build/Products/Release/$(APP_BUNDLE) .

build-universal: generate
ifndef CI
	@echo "\033[33m[WARNING] build-universal はローカルテスト用です。リリースバイナリは CI が作成します。\033[0m"
	@echo "\033[33m  リリース手順: git tag vX.Y.Z && git push origin vX.Y.Z\033[0m"
endif
	xcodebuild -project $(BINARY_NAME).xcodeproj -scheme $(BINARY_NAME) -configuration Release -derivedDataPath $(DERIVED_DATA) ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO build
	cp -R $(DERIVED_DATA)/Build/Products/Release/$(APP_BUNDLE) .

test: generate
	xcodebuild -project $(BINARY_NAME).xcodeproj -scheme $(BINARY_NAME)-tests -configuration Debug -derivedDataPath $(DERIVED_DATA) build
	$(DERIVED_DATA)/Build/Products/Debug/$(BINARY_NAME)-tests

clean:
	rm -rf $(APP_BUNDLE) $(DERIVED_DATA) *.xcodeproj AppIcon.iconset AppIcon.icns
