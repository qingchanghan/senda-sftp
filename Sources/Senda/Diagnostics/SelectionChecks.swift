import AppKit
import Foundation
import SFTPCore

@MainActor
func runSelectionChecks() -> Never {
    NSApplication.shared.setActivationPolicy(.prohibited)
    let domain = "app.senda.selection-check.\(UUID().uuidString)"
    let preferences = UserDefaults(suiteName: domain)!
    let model = AppModel(preferences: preferences, loadFiles: false, loadHosts: false)
    var failures = 0
    func check(_ condition: @autoclosure () -> Bool, _ name: String) {
        if condition() { print("PASS \(name)") }
        else { failures += 1; fputs("FAIL \(name)\n", stderr) }
    }
    let migrationDomain = "app.senda.migration-check.\(UUID().uuidString)"
    let migration = UserDefaults(suiteName: migrationDomain)!
    migration.set("current-host", forKey: "lastHost")
    PreferencesMigration.run(into: migration, legacy: ["lastHost": "old-host", "localPath": "/fixture/local", "remotePath.dev-box": "/fixture/remote", "showHidden": true, "unrelated": "private"])
    check(migration.string(forKey: "lastHost") == "current-host", "migration preserves existing Senda settings")
    check(migration.string(forKey: "localPath") == "/fixture/local" && migration.string(forKey: "remotePath.dev-box") == "/fixture/remote", "migration imports saved local and per-host remote paths")
    check(migration.object(forKey: "unrelated") == nil && migration.bool(forKey: "showHidden"), "migration imports only supported preferences")
    migration.removeObject(forKey: "localPath")
    PreferencesMigration.run(into: migration, legacy: ["localPath": "/fixture/stale"])
    check(migration.object(forKey: "localPath") == nil, "migration runs only once")
    migration.removePersistentDomain(forName: migrationDomain)
    let files = [
        FileEntry(name: "folder", path: "/fixture/folder", permissions: 0o040755),
        FileEntry(name: "中文 ' a.txt", path: "/fixture/中文 ' a.txt", permissions: 0o100644),
        FileEntry(name: "b.bin", path: "/fixture/b.bin", permissions: 0o100644),
        FileEntry(name: ".hidden", path: "/fixture/.hidden", permissions: 0o100644)
    ]
    model.localFiles = files; model.remoteFiles = files
    var view = FileTable(model: model, remote: false, entries: model.visibleLocal)
    let coordinator = view.makeCoordinator()
    let actualScroll = view.makeScrollView(coordinator: coordinator)
    let table = coordinator.table as! FileNSTableView
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 350), styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = actualScroll; window.makeFirstResponder(table); table.reloadData()
    check(table.allowsMultipleSelection, "native table enables multiple selection")
    table.selectRowIndexes(IndexSet([0, 2]), byExtendingSelection: false)
    check(model.localSelection == Set([files[0].path, files[2].path]), "noncontiguous selection reaches the model")
    table.selectRowIndexes(IndexSet(integersIn: 0...2), byExtendingSelection: false)
    check(model.selectedEntries(remote: false).count == 3, "range selection includes every item")
    table.deselectAll(nil)
    let commandA = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "a", charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0)!
    check(table.performKeyEquivalent(with: commandA), "Command-A is handled by the focused file table")
    check(table.selectedRowIndexes.count == 3 && model.localSelection.count == 3, "Command-A selects visible files and folders")
    let clear = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command, .shift], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "A", charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0)!
    table.keyDown(with: clear)
    check(model.localSelection.isEmpty, "Shift-Command-A clears selection")
    model.localSelection = [files[2].path]
    view = FileTable(model: model, remote: false, entries: Array(model.visibleLocal.reversed()))
    coordinator.parent = view; view.synchronizeSelection(coordinator: coordinator)
    check(table.selectedRowIndexes == IndexSet(integer: 0), "selection follows file identity after list reordering")
    let sizeColumn = NSTableColumn(identifier: .init("size"))
    let beforeSize = (coordinator.tableView(table, viewFor: sizeColumn, row: 0) as? NSTableCellView)?.textField?.stringValue
    let updatedFile = FileEntry(name: files[2].name, path: files[2].path, size: 4096, permissions: files[2].permissions)
    view = FileTable(model: model, remote: false, entries: [updatedFile, files[1], files[0]])
    coordinator.parent = view; view.synchronizeSelection(coordinator: coordinator)
    let afterSize = (coordinator.tableView(table, viewFor: sizeColumn, row: 0) as? NSTableCellView)?.textField?.stringValue
    check(beforeSize != afterSize && afterSize == ByteCountFormatter.string(fromByteCount: 4096, countStyle: .file), "refresh invalidates cached file sizes")
    view = FileTable(model: model, remote: false, entries: Array(model.visibleLocal.reversed()))
    coordinator.parent = view; view.synchronizeSelection(coordinator: coordinator)
    model.showHidden = true; model.selectAll(remote: false)
    check(model.localSelection.count == 4, "show-hidden all selects hidden files too")
    model.showHidden = false
    check(model.localSelection.count == 3 && !model.localSelection.contains(files[3].path), "hiding files removes them from bulk selection")
    model.selectAll(remote: true)
    check(model.selectedEntries(remote: true).count == 3, "remote select-all uses only visible files")
    model.deselectAll(remote: true)
    check(model.remoteSelection.isEmpty, "remote clear-selection is independent of local selection")

    let board = NSPasteboard(name: .init("app.senda.selection-check.\(UUID().uuidString)"))
    let localWriters = (0..<3).compactMap { coordinator.tableView(table, pasteboardWriterForRow: $0) }
    board.clearContents()
    check(board.writeObjects(localWriters), "batch local drag writes multiple pasteboard items")
    let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    check(Set(urls.map(\.path)) == Set(files.prefix(3).map(\.path)), "batch local drag preserves every path")
    model.connectedHost = "fixture-host"
    let remote = FileTable(model: model, remote: true, entries: model.visibleRemote)
    let remoteCoordinator = remote.makeCoordinator()
    let writers = (0..<3).compactMap { remoteCoordinator.tableView(table, pasteboardWriterForRow: $0) as? NSFilePromiseProvider }
    board.clearContents()
    check(board.writeObjects(writers), "batch remote drag writes one native promise per item")
    let payloadType = NSPasteboard.PasteboardType("app.senda.remote-file")
    let payloads = board.pasteboardItems?.compactMap { $0.data(forType: payloadType) } ?? []
    check(payloads.count == 3, "batch remote drag preserves all internal download payloads")
    let names = writers.compactMap { $0.delegate?.filePromiseProvider($0, fileNameForType: $0.fileType) }
    check(names == files.prefix(3).map(\.name), "file-promise delegates retain every selected filename")
    board.releaseGlobally(); window.orderOut(nil); model.shutdown()
    preferences.removePersistentDomain(forName: domain)
    print("Selection and batch-drag checks: \(failures) failures")
    exit(failures == 0 ? 0 : 1)
}
