.PHONY: build clean run release notary-setup verify-signing

# Signing / notarization config
SIGN_ID         = Developer ID Application: Jesús Jaime Ortega Cruz (GU57FJMCH4)
TEAM_ID         = GU57FJMCH4
NOTARY_PROFILE  = islands-notary
ENTITLEMENTS    = Resources/Islands.entitlements

# Override on the command line: make release VERSION=0.1.0-beta
VERSION ?= dev

build:
	rm -rf Islands.app
	swift build -c release
	mkdir -p Islands.app/Contents/MacOS
	mkdir -p Islands.app/Contents/Resources
	cp .build/release/Islands Islands.app/Contents/MacOS/
	cp Resources/Info.plist Islands.app/Contents/
	cp Resources/Islands.icns Islands.app/Contents/Resources/
	cp Resources/StatusBarIcon.svg Islands.app/Contents/Resources/
	cp Resources/settings-bg.png Islands.app/Contents/Resources/
	cp Resources/video-islands.mp4 Islands.app/Contents/Resources/
	mkdir -p Islands.app/Contents/Resources/Fonts
	cp Resources/Fonts/*.ttf Islands.app/Contents/Resources/Fonts/

clean:
	rm -rf .build Islands.app dist

run: build
	open Islands.app

# Build, codesign with Developer ID + hardened runtime, notarize, and (if Xcode
# stapler is available) staple. Outputs dist/Islands-<VERSION>.zip ready for
# upload to GitHub Releases.
#
# Usage: make release VERSION=0.1.0-beta
release: build
	@if [ "$(VERSION)" = "dev" ]; then \
		echo "ERROR: pass VERSION=x.y.z (e.g. make release VERSION=0.1.0-beta)"; \
		exit 1; \
	fi
	@mkdir -p dist
	@echo "==> Codesigning Islands.app with Developer ID + hardened runtime"
	codesign --force --options runtime --timestamp \
		--entitlements $(ENTITLEMENTS) \
		--sign "$(SIGN_ID)" \
		Islands.app
	codesign --verify --strict --verbose=2 Islands.app
	@echo "==> Zipping for notary submission"
	rm -f dist/Islands-$(VERSION).zip
	ditto -c -k --keepParent Islands.app dist/Islands-$(VERSION).zip
	@echo "==> Submitting to Apple notary service (this can take 1-15 min)"
	xcrun notarytool submit dist/Islands-$(VERSION).zip \
		--keychain-profile $(NOTARY_PROFILE) \
		--wait
	@echo "==> Notarization accepted. Attempting to staple"
	@if xcrun --find stapler >/dev/null 2>&1; then \
		xcrun stapler staple Islands.app && \
		rm dist/Islands-$(VERSION).zip && \
		ditto -c -k --keepParent Islands.app dist/Islands-$(VERSION).zip && \
		echo "==> Stapled and re-zipped"; \
	else \
		echo "==> stapler not found (full Xcode required); shipping without staple. Online Gatekeeper verification will still pass."; \
	fi
	@echo "==> Final Gatekeeper assessment:"
	-spctl -a -vvv -t install Islands.app
	@echo ""
	@echo "Release ready: dist/Islands-$(VERSION).zip"
	@echo "Next: gh release create v$(VERSION) dist/Islands-$(VERSION).zip --title v$(VERSION) --prerelease"

# Inspect the signature on the current Islands.app bundle.
verify-signing:
	@echo "==> codesign info:"
	-codesign -dv --verbose=4 Islands.app
	@echo ""
	@echo "==> Gatekeeper assessment:"
	-spctl -a -vvv -t install Islands.app

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
