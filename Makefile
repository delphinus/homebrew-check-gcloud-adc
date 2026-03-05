BINARY_NAME := check-gcloud-adc
INSTALL_DIR := $(HOME)/bin
PLIST_NAME := com.delphinus.check-gcloud-adc.plist
PLIST_SRC := $(CURDIR)/$(PLIST_NAME)
PLIST_DST := $(HOME)/Library/LaunchAgents/$(PLIST_NAME)

.PHONY: build install uninstall clean

build:
	CGO_ENABLED=1 go build \
		-ldflags "-extldflags '-sectcreate __TEXT __info_plist $(CURDIR)/Info.plist'" \
		-o $(INSTALL_DIR)/$(BINARY_NAME) .

install: build
	ln -sf $(PLIST_SRC) $(PLIST_DST)
	launchctl load $(PLIST_DST)

uninstall:
	-launchctl unload $(PLIST_DST)
	rm -f $(PLIST_DST)

clean:
	rm -f $(INSTALL_DIR)/$(BINARY_NAME)
