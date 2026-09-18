APP_NAME   := Mailpit Menubar
BUILD_DIR  := build
APP        := $(BUILD_DIR)/$(APP_NAME).app
CONTENTS   := $(APP)/Contents
BINARY     := .build/release/MailpitMenubar
ICON       := $(BUILD_DIR)/AppIcon.icns
INSTALL_TO := /Applications

.PHONY: all build bundle run install clean

all: bundle

build:
	swift build -c release

$(ICON): Scripts/make-icon.swift
	@mkdir -p $(BUILD_DIR)
	swift Scripts/make-icon.swift $(ICON)

bundle: build $(ICON)
	rm -rf "$(APP)"
	mkdir -p "$(CONTENTS)/MacOS" "$(CONTENTS)/Resources"
	cp "$(BINARY)" "$(CONTENTS)/MacOS/MailpitMenubar"
	cp Resources/Info.plist "$(CONTENTS)/Info.plist"
	cp "$(ICON)" "$(CONTENTS)/Resources/AppIcon.icns"
	codesign --force --sign - "$(APP)"
	@echo "Built $(APP)"

run: bundle
	pkill -x MailpitMenubar && sleep 1 || true
	open "$(APP)"

install: bundle
	pkill -x MailpitMenubar && sleep 1 || true
	rm -rf "$(INSTALL_TO)/$(APP_NAME).app"
	cp -R "$(APP)" "$(INSTALL_TO)/"
	open "$(INSTALL_TO)/$(APP_NAME).app"

clean:
	rm -rf .build $(BUILD_DIR)
