import Cocoa
import Combine
import ServiceManagement
import SwiftUI

// Kofein – menubarová appka, ktorá drží spustený `caffeinate -d -i`
// (displej nezhasne, Mac nezaspí). Ľavý klik = popup, pravý klik = rýchle prepnutie.

// MARK: - Model

final class Kofein: ObservableObject {
    @Published private(set) var isOn = false
    @Published private(set) var startedAt: Date?
    @Published private(set) var launchAtLogin = false
    @Published private(set) var loginNote: String?
    @Published var durationMinutes: Int {
        didSet {
            UserDefaults.standard.set(durationMinutes, forKey: Keys.duration)
            if isOn { stop(); start() } // nový limit sa prejaví hneď
        }
    }

    private enum Keys {
        static let lastOn = "lastStateOn"
        static let duration = "durationMinutes"
    }

    private var process: Process?

    init() {
        durationMinutes = UserDefaults.standard.integer(forKey: Keys.duration)
        refreshLoginStatus()
        // Obnov posledný stav (napr. po reštarte so "Spustiť pri prihlásení")
        if UserDefaults.standard.bool(forKey: Keys.lastOn) { start() }
    }

    /// Kedy sa automaticky vypne (ak je nastavený limit)
    var endsAt: Date? {
        guard let startedAt, durationMinutes > 0 else { return nil }
        return startedAt.addingTimeInterval(Double(durationMinutes) * 60)
    }

    func toggle() { isOn ? stop() : start() }

    func start() {
        guard !isOn else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        // -d displej nezhasne, -i systém nezaspí,
        // -w <pid> caffeinate sám skončí, keď skončí táto appka (aj keby spadla)
        var args = ["-d", "-i", "-w", String(ProcessInfo.processInfo.processIdentifier)]
        if durationMinutes > 0 { args += ["-t", String(durationMinutes * 60)] }
        p.arguments = args
        p.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                // skončil sám (timeout / zabitý zvonku) – len ak je to stále "náš" proces
                guard let self, self.process === proc else { return }
                self.process = nil
                self.setOn(false)
            }
        }
        do {
            try p.run()
        } catch {
            NSLog("caffeinate sa nepodarilo spustiť: \(error)")
            return
        }
        process = p
        startedAt = Date()
        setOn(true)
    }

    func stop() {
        let p = process
        process = nil
        p?.terminate()
        setOn(false)
    }

    private func setOn(_ on: Bool) {
        isOn = on
        if !on { startedAt = nil }
        UserDefaults.standard.set(on, forKey: Keys.lastOn)
    }

    // MARK: Spustiť pri prihlásení

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            loginNote = error.localizedDescription
        }
        refreshLoginStatus()
    }

    func refreshLoginStatus() {
        let status = SMAppService.mainApp.status
        launchAtLogin = status == .enabled
        if status == .requiresApproval {
            loginNote = "Treba povoliť v Systémových nastaveniach → Všeobecné → Položky prihlásenia."
        } else if status == .enabled {
            loginNote = nil
        }
    }
}

// MARK: - Popup

struct PopoverView: View {
    @ObservedObject var model: Kofein

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Kofein").font(.headline)
                    Text(model.isOn ? "Displej nezhasne, Mac nezaspí" : "Vypnuté")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Zapnuté", isOn: Binding(get: { model.isOn }, set: { _ in model.toggle() }))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.large)
            }

            statusBox

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Automaticky vypnúť po")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Automaticky vypnúť po", selection: $model.durationMinutes) {
                    Text("Nikdy").tag(0)
                    Text("30 min").tag(30)
                    Text("1 h").tag(60)
                    Text("2 h").tag(120)
                    Text("4 h").tag(240)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 4) {
                Toggle("Spustiť pri prihlásení",
                       isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                    .toggleStyle(.checkbox)
                if let note = model.loginNote {
                    Text(note).font(.caption).foregroundStyle(.orange)
                }
            }

            Divider()

            HStack {
                Text("Tip: pravý klik na ikonu = rýchle prepnutie")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Ukončiť") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
        .padding(16)
        .frame(width: 340)
    }

    private var statusBox: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(model.isOn ? Color.green : Color.secondary.opacity(0.5))
                .frame(width: 8, height: 8)
            if model.isOn, let started = model.startedAt {
                Text("Beží")
                Text(started, style: .timer).monospacedDigit()
                if let end = model.endsAt {
                    Text("· vypne sa o").foregroundStyle(.secondary)
                    Text(end, style: .time).monospacedDigit()
                }
            } else {
                Text("Mac môže normálne zaspať").foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = Kofein()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var iconSubscription: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        let hosting = NSHostingController(rootView: PopoverView(model: model))
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
        popover.behavior = .transient
        popover.animates = true

        iconSubscription = model.$isOn.sink { [weak self] on in self?.updateIcon(on: on) }

        // `Kofein --snapshot out.png` vyrenderuje popup do PNG (na kontrolu vzhľadu) a skončí
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
            snapshot(to: CommandLine.arguments[i + 1])
            NSApp.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
    }

    @objc private func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            model.toggle()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        guard let button = statusItem.button else { return }
        model.refreshLoginStatus()
        // aktivácia appky je nutná, aby sa transient popover zavrel klikom mimo
        if #available(macOS 14, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    private func snapshot(to path: String) {
        let view = NSHostingView(rootView: PopoverView(model: model).background(Color(nsColor: .windowBackgroundColor)))
        view.appearance = NSApp.effectiveAppearance
        view.frame = NSRect(origin: .zero, size: view.fittingSize)
        let window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = view
        window.layoutIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    private func updateIcon(on: Bool) {
        let symbol = on ? "cup.and.saucer.fill" : "cup.and.saucer"
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Kofein") {
            image.isTemplate = true
            statusItem.button?.image = image
        } else {
            statusItem.button?.title = "☕" // fallback, keby SF Symbol chýbal
        }
        statusItem.button?.toolTip = on
            ? "Kofein: ZAPNUTÝ – Mac nezaspí (pravý klik = vypnúť)"
            : "Kofein: vypnutý (pravý klik = zapnúť)"
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // bez ikony v Docku
app.run()
