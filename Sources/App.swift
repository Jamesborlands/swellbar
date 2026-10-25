import AppKit
import ServiceManagement
import SwiftUI
import WebKit

@MainActor
final class SurfModel: ObservableObject {
    @Published private(set) var report: SurfReport?
    @Published private(set) var isLoading = false

    var onUpdate: (() -> Void)?

    var surfRange: Surf.Range? {
        guard let near = report?.nearshore else { return nil }
        return Surf.range(Surf.breakingHeightFt(buoyHeightFt: near.heightFt, periodS: near.periodS))
    }

    var rating: Surf.Rating? {
        guard let range = surfRange, let near = report?.nearshore else { return nil }
        return Surf.rating(range: range, periodS: near.periodS, wind: report?.wind)
    }

    func refresh() {
        guard !isLoading else { return }
        isLoading = true
        Task {
            let fresh = await SurfAPI.fetchReport()
            // Keep the last good report if this fetch came back empty (e.g. offline).
            if fresh.nearshore != nil || report == nil { report = fresh }
            isLoading = false
            onUpdate?()
        }
    }

    func refreshIfStale() {
        if let fetched = report?.fetchedAt, Date().timeIntervalSince(fetched) < 300 { return }
        refresh()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = SurfModel()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // New menu bar items land at the far left, which on a crowded notched Mac is hidden behind the notch.
        // Start Swellbar on the right, next to the system icons; a ⌘-drag afterwards is remembered.
        let positionKey = "NSStatusItem Preferred Position Swellbar"
        if UserDefaults.standard.object(forKey: positionKey) == nil {
            UserDefaults.standard.set(190, forKey: positionKey)
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = "Swellbar"
        statusItem.behavior = []
        statusItem.isVisible = true
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.title = "🌊…"

        popover.behavior = .transient
        popover.animates = true
        let host = NSHostingController(rootView: SurfPopover(model: model))
        host.sizingOptions = []
        popover.contentViewController = host

        model.onUpdate = { [weak self] in
            self?.updateStatusTitle()
            self?.sizePopover()
        }
        model.refresh()

        let timer = Timer(timeInterval: 10 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.refresh() }
        }

        if !UserDefaults.standard.bool(forKey: "didFirstLaunch") {
            UserDefaults.standard.set(true, forKey: "didFirstLaunch")
            try? SMAppService.mainApp.register()
        }

        handleTestArguments()
    }

    private func updateStatusTitle() {
        guard let button = statusItem.button else { return }
        guard let range = model.surfRange else {
            button.attributedTitle = NSAttributedString(string: "🌊--")
            return
        }
        let title = NSMutableAttributedString()
        if let rating = model.rating {
            title.append(NSAttributedString(string: "●", attributes: [
                .foregroundColor: rating.nsColor, .font: NSFont.systemFont(ofSize: 9), .baselineOffset: 1,
            ]))
        }
        title.append(NSAttributedString(string: " \(range.lo)-\(range.hi)\(range.plus ? "+" : "")", attributes: [.font: NSFont.menuBarFont(ofSize: 0)]))
        button.attributedTitle = title
        button.toolTip = "Del Mar: \(range.spaced) · \(range.body)"
    }

    /// Fits the popover to its content, but never taller than the space below the menu bar
    /// (otherwise macOS shoves the top of it off the screen). Anything that doesn't fit scrolls.
    private func sizePopover() {
        guard let view = popover.contentViewController?.view else { return }
        let natural = NSHostingView(rootView: SurfPopover(model: model, scrolls: false)).fittingSize
        let screen = statusItem.button?.window?.screen ?? NSScreen.main
        let room = (screen?.visibleFrame.height ?? 800) - 24
        let size = NSSize(width: natural.width, height: min(natural.height, room))
        popover.contentSize = size
        view.setFrameSize(size)
        if CommandLine.arguments.contains("--print-size") { print("popover:", natural, "->", size, "room", room); fflush(stdout) }
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            model.refreshIfStale()
            sizePopover()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    /// `Swellbar --snapshot out.png` renders the popover to an image once data loads (for testing).
    /// `--surfline-snapshot out.png` does the same for the embedded Surfline window.
    private func handleTestArguments() {
        let args = CommandLine.arguments
        if args.contains("--open-popover") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [self] in
                togglePopover()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [self] in
                    let frame = popover.contentViewController?.view.window?.frame ?? .zero
                    print("popover window:", frame, "screen:", NSScreen.main?.visibleFrame ?? .zero)
                    fflush(stdout)
                }
            }
        }
        if let i = args.firstIndex(of: "--surfline-snapshot"), i + 1 < args.count {
            let out = URL(fileURLWithPath: args[i + 1])
            SurflineWindow.show()
            DispatchQueue.main.asyncAfter(deadline: .now() + 12) {
                SurflineWindow.snapshot(to: out)
            }
        }
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            let out = URL(fileURLWithPath: args[i + 1])
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [self] in
                let host = NSHostingView(rootView: SurfPopover(model: model, scrolls: false).background(Color(white: 0.14)).environment(\.colorScheme, .dark))
                host.frame = NSRect(origin: .zero, size: host.fittingSize)
                let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                window.appearance = NSAppearance(named: .darkAqua)
                window.backgroundColor = NSColor(white: 0.12, alpha: 1)
                window.contentView = host
                host.layoutSubtreeIfNeeded()
                if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                    host.cacheDisplay(in: host.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: out)
                }
                print("menu bar:", statusItem.button?.attributedTitle.string ?? "", "|", statusItem.button?.toolTip ?? "")
                fflush(stdout)
                _ = window
            }
        }
    }
}

/// Surfline's own Del Mar page, in an app window, so their exact report and cams are one click away.
@MainActor
enum SurflineWindow {
    static let spotURL = URL(string: "https://www.surfline.com/surf-report/del-mar/5842041f4e65fad6a77088af")!
    private static var window: NSWindow?

    static func snapshot(to url: URL) {
        guard let web = window?.contentView as? WKWebView else { return }
        web.takeSnapshot(with: nil) { image, _ in
            guard let tiff = image?.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
            try? png.write(to: url)
            print("surfline page:", web.title ?? "", web.url?.absoluteString ?? "")
            fflush(stdout)
        }
    }

    static func show() {
        if window == nil {
            let web = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
            web.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
            web.load(URLRequest(url: spotURL))
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 860),
                             styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            w.title = "Surfline — Del Mar"
            w.contentView = web
            w.isReleasedWhenClosed = false
            w.setFrameAutosaveName("SurflineWindow")
            if !w.setFrameUsingName("SurflineWindow") { w.center() }
            window = w
        } else if let web = window?.contentView as? WKWebView {
            web.reload()
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ enabled: Bool) {
        if enabled { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() }
    }
}
