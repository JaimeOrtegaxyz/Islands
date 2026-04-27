.PHONY: build clean run

build:
	swift build -c release
	mkdir -p Islands.app/Contents/MacOS
	mkdir -p Islands.app/Contents/Resources
	cp .build/release/Islands Islands.app/Contents/MacOS/
	cp Resources/Info.plist Islands.app/Contents/
	cp Resources/Islands.icns Islands.app/Contents/Resources/
	cp Resources/StatusBarIcon.svg Islands.app/Contents/Resources/
	cp settings-bg.png Islands.app/Contents/Resources/
	cp video-islands.mp4 Islands.app/Contents/Resources/
	mkdir -p Islands.app/Contents/Resources/Fonts
	cp Resources/Fonts/*.ttf Islands.app/Contents/Resources/Fonts/

clean:
	rm -rf .build Islands.app

run: build
	open Islands.app
