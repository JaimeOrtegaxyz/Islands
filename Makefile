.PHONY: build clean run release notary-setup verify-signing sparkle-keys

# Signing / notarization config
SIGN_ID         = Developer ID Application: Jesús Jaime Ortega Cruz (GU57FJMCH4)
TEAM_ID         = GU57FJMCH4
NOTARY_PROFILE  = islands-notary
ENTITLEMENTS    = Resources/Islands.entitlements

# Sparkle artifacts (populated by swift build)
SPARKLE_FW      = .build/arm64-apple-macosx/release/Sparkle.framework
SPARKLE_BIN     = .build/artifacts/sparkle/Sparkle/bin

# Override on the command line: make release VERSION=0.1.0-beta
VERSION ?= dev

build:
	rm -rf Islands.app
	swift build -c release
	mkdir -p Islands.app/Contents/MacOS
	mkdir -p Islands.app/Contents/Resources
	mkdir -p Islands.app/Contents/Frameworks
	cp .build/release/Islands Islands.app/Contents/MacOS/
	# swift build sets rpath to @loader_path; add the standard bundle Frameworks
	# path so dyld can find Sparkle.framework at @rpath/Sparkle.framework/...
	install_name_tool -add_rpath @executable_path/../Frameworks Islands.app/Contents/MacOS/Islands
	cp Resources/Info.plist Islands.app/Contents/
	cp Resources/Islands.icns Islands.app/Contents/Resources/
	cp Resources/StatusBarIcon.svg Islands.app/Contents/Resources/
	cp Resources/settings-bg.png Islands.app/Contents/Resources/
	cp Resources/settings-small.png Islands.app/Contents/Resources/
	cp Resources/video-islands.mp4 Islands.app/Contents/Resources/
	mkdir -p Islands.app/Contents/Resources/Fonts
	cp Resources/Fonts/*.ttf Islands.app/Contents/Resources/Fonts/
	ditto $(SPARKLE_FW) Islands.app/Contents/Frameworks/Sparkle.framework

clean:
	rm -rf .build Islands.app dist

run: build
	open Islands.app

# Build, codesign with Developer ID + hardened runtime, package as a DMG,
# notarize, staple, and sign with Sparkle's EdDSA key.
#
# DMG (not zip) because zip extraction by Finder/Archive Utility creates
# AppleDouble metadata files (._FILENAME) that sit in the framework root
# unsealed, breaking spctl's strict assessment. DMGs are filesystem images
# and preserve symlinks + xattrs faithfully regardless of how they're mounted.
#
# Usage: make release VERSION=0.1.0-beta
release: build
	@if [ "$(VERSION)" = "dev" ]; then \
		echo "ERROR: pass VERSION=x.y.z (e.g. make release VERSION=0.1.0-beta)"; \
		exit 1; \
	fi
	@mkdir -p dist
	@echo "==> Codesigning Sparkle.framework (--deep preserves Sparkle's"
	@echo "    resource rules that seal Updater.app, Autoupdate, XPC services)"
	codesign --force --deep --options runtime --timestamp --sign "$(SIGN_ID)" \
		Islands.app/Contents/Frameworks/Sparkle.framework
	@echo "==> Codesigning Islands.app with Developer ID + hardened runtime"
	codesign --force --options runtime --timestamp \
		--entitlements $(ENTITLEMENTS) \
		--sign "$(SIGN_ID)" \
		Islands.app
	codesign --verify --strict --verbose=2 Islands.app
	@echo "==> Building DMG with drag-to-install layout"
	@command -v create-dmg >/dev/null 2>&1 || { \
		echo "ERROR: create-dmg is required. Install with: brew install create-dmg"; \
		exit 1; \
	}
	rm -f dist/Islands-$(VERSION).dmg
	# Build a multi-resolution TIFF for the DMG background so it stays crisp
	# on Retina (where Finder renders the window at 2x pixel density).
	# 1x = 680x400 px @ 72 dpi, 2x = 1360x800 px @ 144 dpi.
	# Notes:
	#   - sips -z forces exact dimensions (--resample* preserves aspect, wrong here)
	#   - DPI metadata (72 vs 144) is what tells Finder these are 1x/2x reps
	#   - tiffutil -cathidpicheck combines + verifies the relationship
	sips -z 400 680 -s dpiHeight 72.0 -s dpiWidth 72.0 \
		Resources/settings-small.png --out dist/dmg-bg-1x.png > /dev/null
	sips -z 800 1360 -s dpiHeight 144.0 -s dpiWidth 144.0 \
		Resources/settings-small.png --out dist/dmg-bg-2x.png > /dev/null
	tiffutil -cathidpicheck dist/dmg-bg-1x.png dist/dmg-bg-2x.png \
		-out dist/dmg-background.tiff > /dev/null
	create-dmg \
		--volname "Islands" \
		--background dist/dmg-background.tiff \
		--window-pos 200 120 \
		--window-size 680 400 \
		--icon-size 110 \
		--icon "Islands.app" 170 200 \
		--app-drop-link 510 200 \
		--hide-extension "Islands.app" \
		--no-internet-enable \
		dist/Islands-$(VERSION).dmg \
		Islands.app
	@echo "==> Submitting DMG to Apple notary service (this can take 1-15 min)"
	xcrun notarytool submit dist/Islands-$(VERSION).dmg \
		--keychain-profile $(NOTARY_PROFILE) \
		--wait
	@echo "==> Notarization accepted. Stapling DMG"
	xcrun stapler staple dist/Islands-$(VERSION).dmg
	@echo "==> Signing DMG with Sparkle EdDSA key for appcast"
	@if [ -x "$(SPARKLE_BIN)/sign_update" ]; then \
		$(SPARKLE_BIN)/sign_update dist/Islands-$(VERSION).dmg > dist/Islands-$(VERSION).sig.txt && \
		echo "==> Sparkle signature written to dist/Islands-$(VERSION).sig.txt"; \
	else \
		echo "WARN: sign_update not found; Sparkle signature skipped."; \
	fi
	@echo "==> Final Gatekeeper assessment on DMG:"
	-spctl -a -vvv -t open --context context:primary-signature dist/Islands-$(VERSION).dmg
	@echo ""
	@echo "Release ready: dist/Islands-$(VERSION).dmg"
	@echo "Sparkle sig:   dist/Islands-$(VERSION).sig.txt"
	@echo "Next: gh release create v$(VERSION) dist/Islands-$(VERSION).dmg --title v$(VERSION) --prerelease"

# Inspect the signature on the current Islands.app bundle.
verify-signing:
	@echo "==> codesign info:"
	-codesign -dv --verbose=4 Islands.app
	@echo ""
	@echo "==> Gatekeeper assessment:"
	-spctl -a -vvv -t execute Islands.app

# Generate (or fetch) the Sparkle EdDSA keypair and write the public key into
# Resources/Info.plist. Run once. The private key lives in your Keychain
# forever; back it up if you ever migrate Macs (generate_keys -x exports it).
sparkle-keys:
	@if [ ! -x "$(SPARKLE_BIN)/generate_keys" ]; then \
		echo "Run 'make build' first to fetch Sparkle tools."; exit 1; \
	fi
	@echo "==> Generating or fetching Sparkle EdDSA keypair"
	@echo "    (Keychain may prompt; click Always Allow.)"
	$(SPARKLE_BIN)/generate_keys
	@echo ""
	@echo "==> Writing public key into Resources/Info.plist"
	@KEY=$$($(SPARKLE_BIN)/generate_keys -p) && \
	plutil -replace SUPublicEDKey -string "$$KEY" Resources/Info.plist && \
	echo "    SUPublicEDKey = $$KEY"

# One-time setup: store notarization credentials in the keychain so the release
# target can submit unattended.
#
# Usage: make notary-setup APPLE_ID=you@example.com APP_PASSWORD=xxxx-xxxx-xxxx-xxxx
#
# Get APP_PASSWORD from https://appleid.apple.com -> Sign-In and Security ->
# App-Specific Passwords. Label it "islands-notary" or similar.
notary-setup:
	@if [ -z "$(APPLE_ID)" ] || [ -z "$(APP_PASSWORD)" ]; then \
		echo "Usage: make notary-setup APPLE_ID=you@example.com APP_PASSWORD=xxxx-xxxx-xxxx-xxxx"; \
		echo ""; \
		echo "Generate APP_PASSWORD at https://appleid.apple.com"; \
		echo "  Account -> Sign-In and Security -> App-Specific Passwords"; \
		exit 1; \
	fi
	xcrun notarytool store-credentials $(NOTARY_PROFILE) \
		--apple-id "$(APPLE_ID)" \
		--team-id $(TEAM_ID) \
		--password "$(APP_PASSWORD)"
