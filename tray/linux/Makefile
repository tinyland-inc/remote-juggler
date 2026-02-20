# RemoteJuggler Linux Tray App Makefile

BINARY_NAME := remote-juggler-tray
VERSION := 2.1.0-beta.1
BUILD_DIR := build

# Build flags
LDFLAGS := -s -w -X main.Version=$(VERSION)

.PHONY: all build clean install uninstall deps

all: build

deps:
	go mod download
	go mod tidy

build: deps
	@mkdir -p $(BUILD_DIR)
	CGO_ENABLED=0 go build -ldflags "$(LDFLAGS)" -o $(BUILD_DIR)/$(BINARY_NAME) .

build-linux-amd64:
	@mkdir -p $(BUILD_DIR)
	GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -ldflags "$(LDFLAGS)" -o $(BUILD_DIR)/$(BINARY_NAME)-linux-amd64 .

build-linux-arm64:
	@mkdir -p $(BUILD_DIR)
	GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -ldflags "$(LDFLAGS)" -o $(BUILD_DIR)/$(BINARY_NAME)-linux-arm64 .

install: build
	install -Dm755 $(BUILD_DIR)/$(BINARY_NAME) $(DESTDIR)/usr/local/bin/$(BINARY_NAME)
	install -Dm644 ../assets/remote-juggler.svg $(DESTDIR)/usr/share/icons/hicolor/scalable/apps/remote-juggler.svg
	install -Dm644 ../../packaging/autostart.desktop $(DESTDIR)/etc/xdg/autostart/remote-juggler-tray.desktop

uninstall:
	rm -f $(DESTDIR)/usr/local/bin/$(BINARY_NAME)
	rm -f $(DESTDIR)/usr/share/icons/hicolor/scalable/apps/remote-juggler.svg
	rm -f $(DESTDIR)/etc/xdg/autostart/remote-juggler-tray.desktop

clean:
	rm -rf $(BUILD_DIR)
	go clean

# Development helpers
run:
	go run .

test:
	go test -v ./...
