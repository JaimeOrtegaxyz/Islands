import AppKit
import AVFoundation
import QuartzCore

final class SplashWindowController: NSWindowController {
    private let onComplete: () -> Void
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var endObserver: NSObjectProtocol?
    private var frameObserver: NSObjectProtocol?
    private var didFinish = false

    init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete

        let screen = NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
        let visible = screen.visibleFrame
        let videoAspect: CGFloat = 2940.0 / 1260.0
        let width = visible.width * 0.618
        let height = width / videoAspect

        let window = SplashWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.ignoresMouseEvents = true
        window.isMovableByWindowBackground = false
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.transient, .ignoresCycle]
        window.center()

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    deinit {
        if let observer = endObserver { NotificationCenter.default.removeObserver(observer) }
        if let observer = frameObserver { NotificationCenter.default.removeObserver(observer) }
    }

    func showAndPlay() {
        guard let window,
              let contentView = window.contentView,
              let url = Bundle.main.url(forResource: "video-islands", withExtension: "mp4") else {
            finish()
            return
        }

        let cornerRadius: CGFloat = 10

        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = cornerRadius
        contentView.layer?.masksToBounds = true
        contentView.layer?.backgroundColor = NSColor.black.cgColor

        let player = AVPlayer(url: url)
        player.actionAtItemEnd = .pause

        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.frame = contentView.bounds
        playerLayer.videoGravity = .resizeAspect
        playerLayer.cornerRadius = cornerRadius
        playerLayer.masksToBounds = true
        playerLayer.backgroundColor = NSColor.black.cgColor
        contentView.layer?.addSublayer(playerLayer)

        contentView.postsFrameChangedNotifications = true
        frameObserver = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: contentView,
            queue: .main
        ) { [weak playerLayer, weak contentView] _ in
            guard let layer = playerLayer, let view = contentView else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.frame = view.bounds
            CATransaction.commit()
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            self?.fadeOutAndFinish()
        }

        self.player = player
        self.playerLayer = playerLayer

        window.alphaValue = 0
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)

        player.play()

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.4
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        })
    }

    private func fadeOutAndFinish() {
        guard let window else {
            finish()
            return
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.55
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            window.orderOut(nil)
            self?.finish()
        })
    }

    private func finish() {
        guard !didFinish else { return }
        didFinish = true
        player?.pause()
        onComplete()
    }
}

// Borderless windows can't become key by default — we don't need keyboard focus
// for the splash, but overriding canBecomeKey/canBecomeMain ensures the window
// renders and animates correctly when the app is activated.
private final class SplashWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
