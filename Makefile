.PHONY: build clean run

build:
	swift build -c release
	mkdir -p Islands.app/Contents/MacOS
	mkdir -p Islands.app/Contents/Resources
	cp .build/release/Islands Islands.app/Contents/MacOS/
	cp Resources/Info.plist Islands.app/Contents/
	cp Resources/Islands.icns Islands.app/Contents/Resources/
	cp Resources/StatusBarIcon.svg Islands.app/Contents/Resources/
	cp settings-bg.webp Islands.app/Contents/Resources/

clean:
	rm -rf .build Islands.app

run: build
	open Islands.app
