APP_NAME := Bucky
CONFIGURATION := release
EXECUTABLE := .build/$(CONFIGURATION)/$(APP_NAME)
APP_DIR := build/$(APP_NAME).app
CONTENTS_DIR := $(APP_DIR)/Contents
MACOS_DIR := $(CONTENTS_DIR)/MacOS
RESOURCES_DIR := $(CONTENTS_DIR)/Resources

.PHONY: build bundle run clean perf perf-baseline

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

perf:
	swift test --filter LauncherFilterPerformanceTests

perf-baseline:
	BUCKY_PERF_UPDATE_BASELINE=1 BUCKY_PERF_GIT_COMMIT="$$(git rev-parse --short HEAD 2>/dev/null || true)" swift test --filter LauncherFilterPerformanceTests
