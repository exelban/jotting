APP = Jotting
BUILD_DIR = $(CURDIR)/build
DERIVED_DATA = $(BUILD_DIR)/DerivedData
APP_PATH = $(DERIVED_DATA)/Build/Products/Release/$(APP).app
DMG_NAME = jotting.dmg
DMG_PATH = $(BUILD_DIR)/$(DMG_NAME)
NOTARY_PROFILE ?= AC_PASSWORD
DEVELOPMENT_TEAM ?= RP2S87B72W

.PHONY: build lint

build: lint
	xcodebuild -project "$(APP).xcodeproj" -scheme "$(APP)" \
		-configuration Release -destination 'generic/platform=macOS' \
		-derivedDataPath "$(DERIVED_DATA)" CODE_SIGN_STYLE=Manual CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
		DEVELOPMENT_TEAM="$(DEVELOPMENT_TEAM)" CODE_SIGN_IDENTITY="Developer ID Application" OTHER_CODE_SIGN_FLAGS=--timestamp build
	codesign --verify --strict "$(APP_PATH)"
	@set -eu; \
	stage=$$(mktemp -d "$(BUILD_DIR)/dmg.XXXXXX"); \
	trap 'rm -rf "$$stage"' EXIT; \
	mkdir "$$stage/volume"; \
	ditto "$(APP_PATH)" "$$stage/volume/$(APP).app"; \
	swift -e 'import AppKit' \
		-e 'let image = NSImage(size: NSSize(width: 500, height: 300), flipped: true) { rect in' \
		-e '    NSColor.white.setFill(); rect.fill()' \
		-e '    let arrow = NSBezierPath()' \
		-e '    arrow.move(to: NSPoint(x: 225, y: 175)); arrow.line(to: NSPoint(x: 275, y: 175))' \
		-e '    arrow.move(to: NSPoint(x: 253, y: 153)); arrow.line(to: NSPoint(x: 275, y: 175)); arrow.line(to: NSPoint(x: 253, y: 197))' \
		-e '    NSColor.black.setStroke(); arrow.lineWidth = 2; arrow.stroke(); return true' \
		-e '}' \
		-e 'try image.tiffRepresentation!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))' \
		"$$stage/background.tiff"; \
	if command -v create-dmg >/dev/null; then \
		create_dmg=create-dmg; \
	else \
		git clone --depth 1 https://github.com/create-dmg/create-dmg "$$stage/create-dmg"; \
		create_dmg="$$stage/create-dmg/create-dmg"; \
	fi; \
	"$$create_dmg" --volname "$(APP)" --background "$$stage/background.tiff" \
		--window-pos 200 120 --window-size 500 320 --icon-size 80 \
		--icon "$(APP).app" 125 175 --hide-extension "$(APP).app" --app-drop-link 375 175 \
		"$$stage/$(DMG_NAME)" "$$stage/volume"; \
	codesign --timestamp --sign "Developer ID Application" "$$stage/$(DMG_NAME)"; \
	submit_exit=0; \
	xcrun notarytool submit "$$stage/$(DMG_NAME)" --keychain-profile "$(NOTARY_PROFILE)" --wait \
		--output-format json > "$$stage/submission.json" || submit_exit=$$?; \
	cat "$$stage/submission.json"; \
	status=$$(plutil -extract status raw -o - "$$stage/submission.json" 2>/dev/null) || status=; \
	if [ "$$submit_exit" -ne 0 ] || [ "$$status" != Accepted ]; then \
		if id=$$(plutil -extract id raw -o - "$$stage/submission.json" 2>/dev/null); then \
			xcrun notarytool log "$$id" --keychain-profile "$(NOTARY_PROFILE)"; \
		fi; \
		exit 1; \
	fi; \
	xcrun stapler staple "$$stage/$(DMG_NAME)"; \
	xcrun stapler validate "$$stage/$(DMG_NAME)"; \
	mv -f "$$stage/$(DMG_NAME)" "$(DMG_PATH)"
	open -R "$(DMG_PATH)"

lint:
	swiftlint lint --strict --no-cache Jotting
