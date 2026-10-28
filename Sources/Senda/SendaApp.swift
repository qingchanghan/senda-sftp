import AppKit
import SwiftUI
import SFTPCore

@main
struct SendaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model: AppModel

    init() {
        if CommandLine.arguments.contains("--probe") { runProbe() }
        if CommandLine.arguments.contains("--native-checks") { runNativeChecks() }
        if CommandLine.arguments.contains("--selection-checks") { runSelectionChecks() }
        if CommandLine.arguments.contains("--address-checks") { runAddressChecks() }
        if CommandLine.arguments.contains("--speed-checks") { runSpeedChecks() }
        if CommandLine.arguments.contains("--batch-checks") { runBatchChecks() }
        if CommandLine.arguments.contains("--performance-checks") { runPerformanceChecks() }
        // OpenSSH invokes the same executable with the authentication prompt as its only argument.
        if ProcessInfo.processInfo.environment["SENDA_ASKPASS"] == "1" || (ProcessInfo.processInfo.environment["SSH_ASKPASS_REQUIRE"] == "force" && CommandLine.arguments.count > 1 && !CommandLine.arguments[1].hasPrefix("--")) { runAskpass() }
        if CommandLine.arguments.contains("--demo") {
            NSApplication.shared.appearance = NSAppearance(named: CommandLine.arguments.contains("--dark") ? .darkAqua : .aqua)
            _model = StateObject(wrappedValue: DemoData.model())
        } else {
            PreferencesMigration.run()
            _model = StateObject(wrappedValue: AppModel())
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .frame(minWidth: T.space(255), minHeight: T.space(170))
                .onAppear { delegate.model = model; NSApplication.shared.activate(ignoringOtherApps: true) }
        }
        .defaultSize(width: T.space(312.5), height: T.space(197.5))
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .pasteboard) {
                Divider()
                Button("全选") { NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil) }.keyboardShortcut("a", modifiers: .command)
                Button("取消选择") { NSApp.sendAction(#selector(NSTableView.deselectAll(_:)), to: nil, from: nil) }.keyboardShortcut("a", modifiers: [.command, .shift])
            }
            CommandMenu("连接") {
                Button("连接主机") { model.connect() }.keyboardShortcut("k", modifiers: .command)
                Button("断开连接") { model.disconnect() }.disabled(!model.connected && !model.isConnecting)
                Divider()
                Button("刷新 SSH 主机") { model.refreshHosts() }
            }
            CommandMenu("文件") {
                Button("刷新文件列表") { model.refreshLocal(); if model.connected { model.refreshRemote() } }.keyboardShortcut("r", modifiers: .command)
                Button("打开本地目录…") { model.chooseLocalFolder() }.keyboardShortcut("o", modifiers: .command)
                Toggle("显示隐藏文件", isOn: $model.showHidden).keyboardShortcut(".", modifiers: [.command, .shift])
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if let model, !model.demoMode, model.activeJobs > 0 {
            let alert = NSAlert(); alert.messageText = "仍有文件正在传输"
            alert.informativeText = "退出会取消未完成的传输。"; alert.addButton(withTitle: "继续传输"); alert.addButton(withTitle: "退出")
            if alert.runModal() == .alertFirstButtonReturn { return .terminateCancel }
        }
        model?.shutdown(); return .terminateNow
    }
}

private func runAskpass() -> Never {
    let app = NSApplication.shared; app.setActivationPolicy(.accessory)
    let prompt = CommandLine.arguments.dropFirst().joined(separator: " ")
    let alert = NSAlert(); alert.messageText = "Senda · SSH 身份验证"; alert.informativeText = prompt
    let hostConfirmation = prompt.contains("yes/no") || ProcessInfo.processInfo.environment["SSH_ASKPASS_PROMPT"] == "confirm"
    if hostConfirmation {
        alert.addButton(withTitle: "信任并连接"); alert.addButton(withTitle: "取消")
    } else {
        alert.addButton(withTitle: "继续"); alert.addButton(withTitle: "取消")
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: T.space(90), height: T.space(6.5)))
        alert.accessoryView = field; alert.window.initialFirstResponder = field
    }
    app.activate(ignoringOtherApps: true)
    guard alert.runModal() == .alertFirstButtonReturn else { exit(1) }
    let answer = hostConfirmation ? "yes" : (alert.accessoryView as? NSSecureTextField)?.stringValue ?? ""
    FileHandle.standardOutput.write(Data((answer + "\n").utf8)); exit(0)
}

private func runProbe() -> Never {
    // Read-only diagnostics usable without the UI. A distinct command avoids accidental writes.
    guard let index = CommandLine.arguments.firstIndex(of: "--probe"), CommandLine.arguments.count > index + 1 else {
        fputs("Usage: Senda --probe <ssh-host> [remote-directory]\n", stderr); exit(2)
    }
    let host = CommandLine.arguments[index + 1]
    let path = CommandLine.arguments.count > index + 2 ? CommandLine.arguments[index + 2] : "."
    do {
        let session = try SFTPSession(host: host)
        defer { session.stop() }
        try session.handshake()
        let resolved = try session.realpath(path), entries = try session.list(resolved)
        print("Connected: \(host)\nDirectory: \(resolved)\nEntries: \(entries.count)")
        for entry in entries.prefix(12) { print("\(entry.isDirectory ? "d" : "-")  \(entry.size)  \(entry.name)") }
        exit(0)
    } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
}
