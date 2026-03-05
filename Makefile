BINARY_NAME := check-gcloud-adc

.PHONY: build clean

build:
	CGO_ENABLED=1 go build \
		-ldflags "-extldflags '-sectcreate __TEXT __info_plist $(CURDIR)/Info.plist'" \
		-o $(BINARY_NAME) .

clean:
	rm -f $(BINARY_NAME)
