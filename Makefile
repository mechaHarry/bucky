APP_NAME := Bucky
CONFIGURATION := release
EXECUTABLE := .build/$(CONFIGURATION)/$(APP_NAME)
APP_DIR := build/$(APP_NAME).app
CONTENTS_DIR := $(APP_DIR)/Contents
MACOS_DIR := $(CONTENTS_DIR)/MacOS
RESOURCES_DIR := $(CONTENTS_DIR)/Resources

.PHONY: build bundle run clean

build:
	swift build -c $(CONFIGURATION)

bundle: build
	mkdir -p "$(MACOS_DIR)"
	mkdir -p "$(RESOURCES_DIR)"
	cp "$(EXECUTABLE)" "$(MACOS_DIR)/$(APP_NAME)"
	cp "packaging/Info.plist" "$(CONTENTS_DIR)/Info.plist"
	chmod +x "$(MACOS_DIR)/$(APP_NAME)"

run: bundle
	open "$(APP_DIR)"

clean:
	swift package clean
	rm -rf build
