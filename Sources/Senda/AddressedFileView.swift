import SwiftUI
import SFTPCore

/// Beautiful UI records surface, task metadata and capsule Button, in file mode.
@MainActor
struct AddressedFileView: View {
    @ObservedObject var model: AppModel
    let file: FileEntry
    let remote: Bool

    private var destination: String { remote ? model.localPath : model.remotePath }
    private var destinationMachine: String { remote ? "我的 Mac" : model.connectedHost }

    var body: some View {
        VStack(alignment: .leading, spacing: T.space(4)) {
            HStack(spacing: T.space(2)) {
                SendaBadge(title: "文件直达", foreground: T.accent, background: T.accentTint)
                Spacer(minLength: T.space(2))
                Text(ByteCountFormatter.string(fromByteCount: Int64(clamping: file.size), countStyle: .file))
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(T.ink2)
            }
            HStack(alignment: .center, spacing: T.space(3)) {
                Image(systemName: "doc.text")
                    .font(.system(size: 24, weight: .light)).foregroundStyle(T.accent)
                    .frame(width: T.space(12), height: T.space(14))
                    .background(RoundedRectangle(cornerRadius: T.radiusControl).fill(T.accentTint))
                VStack(alignment: .leading, spacing: T.space(1.5)) {
                    Text(file.name).font(.system(size: 15, weight: .semibold))
                        .lineLimit(2).truncationMode(.middle).textSelection(.enabled).help(file.name)
                    Text(remote ? "远程文件 · 可直接下载" : "本地文件 · 可直接上传")
                        .font(.system(size: 11)).foregroundStyle(T.ink2)
                }
            }
            SendaRule()
            VStack(alignment: .leading, spacing: T.space(1.5)) {
                Text(remote ? "下载到" : "上传到").font(.system(size: 10, weight: .medium)).foregroundStyle(T.ink3)
                if model.connected {
                    Label(destinationMachine, systemImage: remote ? "laptopcomputer" : "server.rack")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(T.ink2)
                    Text(destination).font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(T.ink2).lineLimit(2).truncationMode(.middle)
                        .textSelection(.enabled).help(destination)
                } else {
                    Text("连接开发机后即可上传").font(.system(size: 11)).foregroundStyle(T.ink2)
                }
            }
            Spacer(minLength: T.space(0))
            HStack(spacing: T.space(2)) {
                Button {
                    if remote { model.navigateRemote(model.remotePath) }
                    else { model.navigateLocal(model.localPath) }
                } label: {
                    Label("所在文件夹", systemImage: "folder").font(.system(size: 11))
                }.buttonStyle(SendaActionButtonStyle()).help("打开所在文件夹")
                Spacer(minLength: T.space(0))
                Button { model.transferAddressFile(remote: remote) } label: {
                    Label(remote ? "下载此文件" : "上传此文件", systemImage: remote ? "arrow.down" : "arrow.up")
                        .font(.system(size: 11, weight: .medium))
                }.buttonStyle(SendaActionButtonStyle(prominent: true))
                    .disabled(!model.canTransferAddressFile(remote: remote))
                    .help("传输到对侧当前文件夹；重名时自动保留两份")
            }
        }
        .padding(T.space(4)).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
