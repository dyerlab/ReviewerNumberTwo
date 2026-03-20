SCHEME    = ReviewerNumberTwo
PROJECT   = ReviewerNumberTwo.xcodeproj
XCODEBUILD = /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild
INSTALL_DIR = /usr/local/bin
BINARY_NAME = reviewer

BUILT_PRODUCTS_DIR := $(shell $(XCODEBUILD) -scheme $(SCHEME) -project $(PROJECT) \
	-configuration Release -showBuildSettings 2>/dev/null \
	| awk '/^\s*BUILT_PRODUCTS_DIR/{print $$3}')

.PHONY: build install uninstall

build:
	$(XCODEBUILD) -scheme $(SCHEME) -project $(PROJECT) -configuration Release

install: build
	cp "$(BUILT_PRODUCTS_DIR)/$(SCHEME)" "$(INSTALL_DIR)/$(BINARY_NAME)"
	@echo "Installed to $(INSTALL_DIR)/$(BINARY_NAME)"

uninstall:
	rm -f "$(INSTALL_DIR)/$(BINARY_NAME)"
	@echo "Removed $(INSTALL_DIR)/$(BINARY_NAME)"
