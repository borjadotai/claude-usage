APP_NAME := ClaudeUsage
SCHEME := ClaudeUsage
BUILD_DIR := build
VERSION := $(shell grep -m1 'MARKETING_VERSION' ClaudeUsage.xcodeproj/project.pbxproj | tr -d ' ;' | cut -d= -f2)

.PHONY: build zip clean

build:
	xcodebuild \
		-scheme $(SCHEME) \
		-configuration Release \
		-derivedDataPath $(BUILD_DIR) \
		CODE_SIGN_IDENTITY="-" \
		CODE_SIGNING_ALLOWED=NO \
		DEVELOPMENT_TEAM="" \
		-quiet
	@echo "Built: $(BUILD_DIR)/Build/Products/Release/$(APP_NAME).app"

zip: build
	cd $(BUILD_DIR)/Build/Products/Release && zip -r -q $(CURDIR)/$(APP_NAME)-$(VERSION).zip $(APP_NAME).app
	@echo "Created: $(APP_NAME)-$(VERSION).zip"
	@shasum -a 256 $(APP_NAME)-$(VERSION).zip

clean:
	rm -rf $(BUILD_DIR) $(APP_NAME)-*.zip
