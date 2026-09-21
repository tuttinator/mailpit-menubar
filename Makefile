APP_NAME   := Mailpit Menubar
BUILD_DIR  := build
APP        := $(BUILD_DIR)/$(APP_NAME).app
CONTENTS   := $(APP)/Contents
BINARY     := .build/release/MailpitMenubar
SPARKLE    := .build/release/Sparkle.framework
ICON       := $(BUILD_DIR)/AppIcon.icns
INSTALL_TO := /Applications

# Ad-hoc by default (local dev). scripts/release.sh passes the Developer ID
# identity, which also turns on the hardened runtime + secure timestamps that
# notarization requires.
SIGN_IDENTITY ?= -
ifeq ($(SIGN_IDENTITY),-)
SIGN_FLAGS :=
else
SIGN_FLAGS := --options runtime --timestamp
endif
CODESIGN := codesign --force --sign "$(SIGN_IDENTITY)" $(SIGN_FLAGS)

SPARKLE_B := $(CONTENTS)/Frameworks/Sparkle.framework/Versions/B

.PHONY: all build bundle sign run install clean

all: bundle

build:
	swift build -c release

$(ICON): Scripts/make-icon.swift
	@mkdir -p $(BUILD_DIR)
	swift Scripts/make-icon.swift $(ICON)

bundle: build $(ICON)
	rm -rf "$(APP)"
	mkdir -p "$(CONTENTS)/MacOS" "$(CONTENTS)/Resources" "$(CONTENTS)/Frameworks"
	cp "$(BINARY)" "$(CONTENTS)/MacOS/MailpitMenubar"
	cp Resources/Info.plist "$(CONTENTS)/Info.plist"
	cp "$(ICON)" "$(CONTENTS)/Resources/AppIcon.icns"
	cp -R "$(SPARKLE)" "$(CONTENTS)/Frameworks/"
	$(MAKE) sign
	@echo "Built $(APP)"

# Sparkle's nested helpers must be signed individually (inside-out) before the
# framework and then the app; `--deep` is not reliable for this.
sign:
	$(CODESIGN) "$(SPARKLE_B)/XPCServices/Installer.xpc"
	$(CODESIGN) --preserve-metadata=entitlements "$(SPARKLE_B)/XPCServices/Downloader.xpc"
	$(CODESIGN) "$(SPARKLE_B)/Autoupdate"
	$(CODESIGN) "$(SPARKLE_B)/Updater.app"
	$(CODESIGN) "$(CONTENTS)/Frameworks/Sparkle.framework"
	$(CODESIGN) "$(APP)"
	codesign --verify --deep --strict "$(APP)"

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
