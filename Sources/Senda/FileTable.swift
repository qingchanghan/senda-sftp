import AppKit
import SwiftUI
import UniformTypeIdentifiers
import SFTPCore

private let remotePasteboardType = NSPasteboard.PasteboardType("app.senda.remote-file")

private struct RemoteDragItem: Codable {
    let host: String
    let name: String
    let path: String
    let size: UInt64
    let permissions: UInt32
    var entry: FileEntry { FileEntry(name: name, path: path, size: size, permissions: permissions) }
}

private final class RemotePromiseProvider: NSFilePromiseProvider {
    var payload: Data?
    override func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        super.writableTypes(for: pasteboard) + [remotePasteboardType]
    }
    override func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        type == remotePasteboardType ? payload : super.pasteboardPropertyList(forType: type)
    }
}

@MainActor
private final class DownloadPromise: NSObject, NSFilePromiseProviderDelegate {
    let entry: FileEntry
    let host: String
    let model: AppModel
    init(entry: FileEntry, host: String, model: AppModel) { self.entry = entry; self.host = host; self.model = model }
    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String { entry.name }
    func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue { .main }
    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, writePromiseTo url: URL, completionHandler: @escaping (Error?) -> Void) {
        Task { @MainActor in
            model.promisedDownload(entry, host: host, destination: url, completion: completionHandler)
        }
    }
}

final class FileNSTableView: NSTableView {
    var enter: (() -> Void)?
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if window?.firstResponder === self, handleSelectionShortcut(event) { return true }
        return super.performKeyEquivalent(with: event)
    }

    private func handleSelectionShortcut(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard event.charactersIgnoringModifiers?.lowercased() == "a" else { return false }
        if modifiers == .command { selectAll(nil); return true }
        if modifiers == [.command, .shift] { deselectAll(nil); return true }
        return false
    }

    override func keyDown(with event: NSEvent) {
        if handleSelectionShortcut(event) { return }
        if event.keyCode == 36 || (event.keyCode == 125 && event.modifierFlags.contains(.command)) { enter?() }
        else { super.keyDown(with: event) }
    }
}

struct FileTable: NSViewRepresentable {
    let model: AppModel
    let remote: Bool
    let entries: [FileEntry]

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        makeScrollView(coordinator: context.coordinator)
    }

    func makeScrollView(coordinator: Coordinator) -> NSScrollView {
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.drawsBackground = false; scroll.borderType = .noBorder
        scroll.scrollerStyle = .overlay
        scroll.contentView.drawsBackground = false
        let table = FileNSTableView()
        table.identifier = NSUserInterfaceItemIdentifier(remote ? "remote-files" : "local-files")
        table.setAccessibilityLabel(remote ? "远程文件列表" : "本地文件列表")
        table.rowHeight = T.space(10); table.intercellSpacing = NSSize(width: T.space(3), height: T.space(0))
        table.usesAlternatingRowBackgroundColors = false; table.backgroundColor = .clear
        table.style = .fullWidth; table.selectionHighlightStyle = .regular
        table.allowsMultipleSelection = true; table.allowsEmptySelection = true; table.allowsColumnSelection = false
        table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        let name = NSTableColumn(identifier: .init("name")); name.title = "名称"; name.minWidth = T.space(37.5); name.width = T.space(65)
        let size = NSTableColumn(identifier: .init("size")); size.title = "大小"; size.width = T.space(20.5); size.minWidth = T.space(16.25); size.maxWidth = T.space(25)
        let modified = NSTableColumn(identifier: .init("modified")); modified.title = "修改时间"; modified.width = T.space(28); modified.minWidth = T.space(25); modified.maxWidth = T.space(35)
        for column in [name, size, modified] {
            column.headerCell = RecordsHeaderCell(textCell: column.title)
            table.addTableColumn(column)
        }
        table.headerView = RecordsHeaderView()
        table.headerView?.frame.size.height = T.space(8)
        table.delegate = coordinator; table.dataSource = coordinator
        table.target = coordinator; table.doubleAction = #selector(Coordinator.openSelection)
        table.enter = { [weak coordinator] in coordinator?.openKeyboardSelection() }
        table.registerForDraggedTypes([.fileURL, remotePasteboardType])
        table.setDraggingSourceOperationMask(.copy, forLocal: false)
        table.setDraggingSourceOperationMask(.copy, forLocal: true)
        scroll.documentView = table
        coordinator.table = table
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        synchronizeSelection(coordinator: coordinator)
    }

    func synchronizeSelection(coordinator: Coordinator) {
        guard let table = coordinator.table else { return }
        let sharedStorage = coordinator.entries.withUnsafeBufferPointer { old in
            entries.withUnsafeBufferPointer { new in old.baseAddress == new.baseAddress && old.count == new.count }
        }
        let changed = !sharedStorage && coordinator.entries != entries
        if !sharedStorage { coordinator.entries = entries }
        if changed {
            coordinator.rebuildIndex()
            coordinator.updating = true; table.reloadData(); coordinator.updating = false
        }
        let selection = remote ? model.remoteSelection : model.localSelection
        guard changed || coordinator.appliedSelection != selection else { return }
        let indices = IndexSet(selection.compactMap { coordinator.pathToRow[$0] })
        if table.selectedRowIndexes != indices {
            coordinator.updating = true; table.selectRowIndexes(indices, byExtendingSelection: false); coordinator.updating = false
        }
        coordinator.appliedSelection = selection
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: FileTable
        var entries: [FileEntry]
        weak var table: NSTableView?
        var updating = false
        var pathToRow: [String: Int] = [:]
        var appliedSelection: Set<String>?
        private struct Presentation { let symbol: String; let size: String; let date: String }
        private var presentations: [String: Presentation] = [:]
        private static var images: [String: NSImage] = [:]
        private static let formatter: DateFormatter = { let value = DateFormatter(); value.dateFormat = "MM-dd HH:mm"; return value }()
        private static let byteFormatter: ByteCountFormatter = { let value = ByteCountFormatter(); value.countStyle = .file; return value }()

        init(_ parent: FileTable) { self.parent = parent; self.entries = parent.entries; super.init(); rebuildIndex() }
        func rebuildIndex() {
            pathToRow = Dictionary(entries.enumerated().map { ($0.element.path, $0.offset) }, uniquingKeysWith: { first, _ in first })
            presentations.removeAll(keepingCapacity: true)
            appliedSelection = nil
        }
        func numberOfRows(in tableView: NSTableView) -> Int { entries.count }
        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { RecordsRowView() }

        func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
            guard entries.indices.contains(row), let column else { return nil }
            let entry = entries[row]
            let presentation: Presentation
            if let cached = presentations[entry.path] { presentation = cached }
            else {
                presentation = Presentation(symbol: entry.isSymbolicLink ? "link" : (entry.isDirectory ? "folder" : icon(for: entry.name)), size: entry.isDirectory ? "—" : Self.byteFormatter.string(fromByteCount: Int64(clamping: entry.size)), date: entry.modified.map(Self.formatter.string) ?? "—")
                presentations[entry.path] = presentation
            }
            let id = column.identifier
            if id.rawValue == "name" {
                let cell = (tableView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView) ?? makeNameCell(id)
                cell.textField?.stringValue = entry.name
                let symbol = presentation.symbol
                if Self.images[symbol] == nil { Self.images[symbol] = NSImage(systemSymbolName: symbol, accessibilityDescription: entry.isDirectory ? "文件夹" : "文件") }
                cell.imageView?.image = Self.images[symbol]
                cell.imageView?.contentTintColor = entry.isDirectory ? SendaTheme.accentNS : T.ink2NS
                cell.toolTip = entry.path
                return cell
            }
            let cell = (tableView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView) ?? makeTextCell(id)
            if id.rawValue == "size" { cell.textField?.stringValue = presentation.size; cell.textField?.alignment = .right }
            else { cell.textField?.stringValue = presentation.date; cell.textField?.alignment = .left }
            return cell
        }

        private func makeTextCell(_ id: NSUserInterfaceItemIdentifier) -> NSTableCellView {
            let cell = NSTableCellView(); cell.identifier = id
            let text = NSTextField(labelWithString: ""); text.translatesAutoresizingMaskIntoConstraints = false
            text.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            text.textColor = T.ink2NS; text.lineBreakMode = .byTruncatingTail
            cell.addSubview(text); cell.textField = text
            NSLayoutConstraint.activate([
                text.leadingAnchor.constraint(equalTo: cell.leadingAnchor), text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -T.space(1)), text.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
            return cell
        }

        private func makeNameCell(_ id: NSUserInterfaceItemIdentifier) -> NSTableCellView {
            let cell = NSTableCellView(); cell.identifier = id
            let icon = NSImageView(); icon.translatesAutoresizingMaskIntoConstraints = false; icon.imageScaling = .scaleProportionallyDown
            let text = NSTextField(labelWithString: ""); text.translatesAutoresizingMaskIntoConstraints = false
            text.textColor = T.inkNS; text.font = .systemFont(ofSize: 12); text.lineBreakMode = .byTruncatingMiddle
            cell.addSubview(icon); cell.addSubview(text); cell.imageView = icon; cell.textField = text
            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: T.space(1)), icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: T.space(5)), icon.heightAnchor.constraint(equalToConstant: T.space(5)),
                text.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: T.space(2)), text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -T.space(1)), text.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
            return cell
        }

        private func icon(for name: String) -> String {
            switch (name as NSString).pathExtension.lowercased() {
            case "py", "rs", "swift", "js", "ts", "cpp", "c", "h", "sh", "json", "yaml", "yml", "toml": return "chevron.left.forwardslash.chevron.right"
            case "png", "jpg", "jpeg", "gif", "webp": return "photo"
            case "zip", "gz", "tar", "xz", "zst", "whl": return "archivebox"
            case "safetensors", "bin", "pt", "pth", "gguf": return "square.stack.3d.up"
            case "md", "txt", "log": return "doc.text"
            default: return "doc"
            }
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !updating, let table else { return }
            let selected = Set(table.selectedRowIndexes.compactMap { entries.indices.contains($0) ? entries[$0].path : nil })
            appliedSelection = selected
            if parent.remote { parent.model.remoteSelection = selected } else { parent.model.localSelection = selected }
        }

        @objc func openSelection() {
            guard let table else { return }
            // Double-click opens the clicked row, rather than the first item in a multi-selection.
            openRow(table.clickedRow >= 0 ? table.clickedRow : table.selectedRow)
        }

        func openKeyboardSelection() { openRow(table?.selectedRow ?? -1) }

        private func openRow(_ row: Int) {
            guard entries.indices.contains(row) else { return }
            let entry = entries[row]
            if entry.isDirectory {
                if parent.remote { parent.model.navigateRemote(entry.path) } else { parent.model.navigateLocal(entry.path) }
            } else if entry.isSymbolicLink {
                parent.model.alertMessage = "首版暂不打开或传输符号链接。"
            } else if parent.remote { parent.model.enqueueDownload(entry, directory: URL(fileURLWithPath: parent.model.localPath)) }
            else { NSWorkspace.shared.open(URL(fileURLWithPath: entry.path)) }
        }

        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
            guard entries.indices.contains(row) else { return nil }
            let entry = entries[row]
            guard !entry.isSymbolicLink else { return nil }
            if !parent.remote { return NSURL(fileURLWithPath: entry.path) }
            let delegate = DownloadPromise(entry: entry, host: parent.model.connectedHost, model: parent.model)
            let type = entry.isDirectory ? UTType.folder.identifier : (UTType(filenameExtension: (entry.name as NSString).pathExtension)?.identifier ?? UTType.data.identifier)
            let provider = RemotePromiseProvider(fileType: type, delegate: delegate)
            provider.userInfo = delegate // NSFilePromiseProvider's delegate is weak.
            provider.payload = try? JSONEncoder().encode(RemoteDragItem(host: parent.model.connectedHost, name: entry.name, path: entry.path, size: entry.size, permissions: entry.permissions))
            return provider
        }

        func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession, willBeginAt screenPoint: NSPoint, forRowIndexes rowIndexes: IndexSet) {
            session.draggingFormation = rowIndexes.count > 1 ? .stack : .none
            session.animatesToStartingPositionsOnCancelOrFail = true
        }

        func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation operation: NSTableView.DropOperation) -> NSDragOperation {
            let board = info.draggingPasteboard
            let isRemote = board.availableType(from: [remotePasteboardType]) != nil
            guard parent.remote ? (parent.model.connected && !isRemote && board.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])) : isRemote else { return [] }
            info.numberOfValidItemsForDrop = board.pasteboardItems?.count ?? 0
            info.draggingFormation = .stack
            if row >= 0, row < entries.count, entries[row].isDirectory { tableView.setDropRow(row, dropOperation: .on) }
            else { tableView.setDropRow(-1, dropOperation: .on) }
            return .copy
        }

        func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
            acceptDrop(from: info.draggingPasteboard, row: row)
        }

        @discardableResult
        func acceptDrop(from pasteboard: NSPasteboard, row: Int) -> Bool {
            let destination: String
            if row >= 0, entries.indices.contains(row), entries[row].isDirectory { destination = entries[row].path }
            else { destination = parent.remote ? parent.model.remotePath : parent.model.localPath }
            if parent.remote {
                let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
                parent.model.upload(urls, to: destination); return !urls.isEmpty
            }
            let payloads = pasteboard.pasteboardItems?.compactMap { $0.data(forType: remotePasteboardType) }.compactMap { try? JSONDecoder().decode(RemoteDragItem.self, from: $0) }.filter { RemotePath.safeName($0.name) } ?? []
            // Publish one queue change for the whole drop, even for a very large selection.
            parent.model.enqueueDownloads(payloads.map { ($0.entry, $0.host) }, directory: URL(fileURLWithPath: destination))
            return !payloads.isEmpty
        }
    }
}

/// Beautiful UI RecordsTable: quiet header, precise rules, tinted selection.
private final class RecordsHeaderView: NSTableHeaderView {
    override func draw(_ dirtyRect: NSRect) {
        T.insetNS.setFill(); bounds.fill()
        super.draw(dirtyRect)
    }
}
private final class RecordsHeaderCell: NSTableHeaderCell {
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        T.insetNS.setFill(); cellFrame.fill()
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: T.ink2NS]
        let text = NSAttributedString(string: stringValue, attributes: attributes)
        text.draw(at: NSPoint(x: cellFrame.minX + T.space(2), y: cellFrame.midY - text.size().height / 2))
        T.lineNS.setFill()
        NSRect(x: cellFrame.minX, y: cellFrame.maxY - T.space(0.25), width: cellFrame.width, height: T.space(0.25)).fill()
    }
}
private final class RecordsRowView: NSTableRowView {
    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }
    override func drawBackground(in dirtyRect: NSRect) {
        T.surfaceNS.setFill(); bounds.fill()
        T.lineSoftNS.setFill()
        NSRect(x: 0, y: bounds.maxY - T.space(0.25), width: bounds.width, height: T.space(0.25)).fill()
    }
    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }
        T.accentTintNS.setFill(); bounds.fill()
        T.accentNS.setFill()
        NSRect(x: 0, y: 0, width: T.space(0.5), height: bounds.height).fill()
    }
}
