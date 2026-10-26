import AppKit
import SwiftUI
import SFTPCore

private let sendaAccent = T.accent

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var settings = false
    var body: some View {
        HStack(spacing: T.space(0)) {
            HostSidebar(model: model).frame(width: T.space(56))
            VStack(spacing: T.space(0)) {
                header
                HSplitView {
                    filePane(remote: false).frame(minWidth: T.space(90)).padding(.leading, T.space(4)).padding(.trailing, T.space(2))
                    filePane(remote: true).frame(minWidth: T.space(90)).padding(.leading, T.space(2)).padding(.trailing, T.space(4))
                }.padding(.top, T.space(1)).padding(.bottom, T.space(3))
                transfers.frame(height: T.space(56)).padding(.horizontal, T.space(4))
                statusBar
            }
            .background(SendaTheme.canvas)
        }
        .foregroundStyle(T.ink)
        .tint(sendaAccent)
        .alert("Senda", isPresented: Binding(get: { model.alertMessage != nil }, set: { if !$0 { model.alertMessage = nil } })) {
            Button("知道了", role: .cancel) { model.alertMessage = nil }
        } message: { Text(model.alertMessage ?? "") }
    }

    private var header: some View {
        HStack(spacing: T.space(4)) {
            VStack(alignment: .leading, spacing: T.space(1.25)) {
                Text("文件工作台").font(.system(size: 22, weight: .semibold))
                Text("从这里，到那里。").font(.system(size: 11)).foregroundStyle(T.ink2)
            }
            Spacer(minLength: T.space(3))
            HStack(spacing: T.space(2)) {
                Circle().fill(model.connected ? sendaAccent : T.ink3).frame(width: T.space(1.5), height: T.space(1.5))
                Image(systemName: "terminal").foregroundStyle(T.ink2)
                TextField("SSH 主机别名", text: $model.hostInput).textFieldStyle(.plain).font(.system(size: 12, design: .monospaced))
                    .frame(width: T.space(35)).onSubmit { model.connect() }.accessibilityLabel("SSH 主机别名")
                if model.isConnecting { ProgressView().controlSize(.mini) }
            }
            .padding(.horizontal, T.space(2.5)).padding(.vertical, T.space(2.25))
            .background(RoundedRectangle(cornerRadius: T.radiusControl).fill(SendaTheme.surface))
            .overlay(RoundedRectangle(cornerRadius: T.radiusControl).strokeBorder(SendaTheme.border))
            Button {
                if model.connected || model.isConnecting { model.disconnect() } else { model.connect() }
            } label: {
                Text(model.connected ? "断开" : (model.isConnecting ? "取消" : "连接"))
                    .font(.system(size: 12, weight: .semibold)).frame(width: T.space(10))
            }.buttonStyle(SendaActionButtonStyle(prominent: !model.connected && !model.isConnecting))
            Button { settings.toggle() } label: { Image(systemName: "slider.horizontal.3").font(.system(size: 15)) }
                .buttonStyle(SendaIconButtonStyle()).foregroundStyle(T.ink2).help("连接设置")
                .popover(isPresented: $settings, arrowEdge: .bottom) { settingsView }
        }
        .padding(.horizontal, T.space(6)).padding(.top, T.space(6)).padding(.bottom, T.space(5))
    }

    private var settingsView: some View {
        VStack(alignment: .leading, spacing: T.space(4)) {
            Text("连接设置").font(.headline)
            Toggle("显示隐藏文件", isOn: $model.showHidden)
            Divider()
            Text("代理程序 PATH").font(.system(size: 12, weight: .semibold))
            Text("如果 ProxyCommand 使用特定 Python 环境，可填写它的 bin 目录；多个目录以冒号分隔。").font(.system(size: 11)).foregroundStyle(T.ink2).fixedSize(horizontal: false, vertical: true)
            TextField("例如 /Users/you/miniconda3/bin", text: $model.proxyPath).textFieldStyle(.roundedBorder).font(.system(size: 11, design: .monospaced))
            Text("已自动补全常用 Conda、Homebrew 路径。修改后重新连接生效。").font(.system(size: 10)).foregroundStyle(T.ink2)
            Button("打开 SSH 配置") { NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh/config")) }
        }.padding(T.space(5.5)).frame(width: T.space(87.5))
    }

    private func filePane(remote: Bool) -> some View {
        let files = remote ? model.visibleRemote : model.visibleLocal
        let selection = remote ? model.remoteSelection : model.localSelection
        return VStack(spacing: T.space(0)) {
            HStack(spacing: T.space(2)) {
                Image(systemName: remote ? "server.rack" : "laptopcomputer").font(.system(size: 14)).foregroundStyle(sendaAccent)
                    .frame(width: T.space(7), height: T.space(7)).background(RoundedRectangle(cornerRadius: T.radiusControl).fill(T.accentTint))
                Text(remote ? "远程开发机" : "我的 Mac").font(.system(size: 12, weight: .semibold))
                Text(remote ? "REMOTE" : "LOCAL").font(.system(size: 8, weight: .medium, design: .monospaced)).tracking(1.2).foregroundStyle(T.ink3)
                Spacer()
                if remote && model.isRemoteLoading { ProgressView().controlSize(.mini) }
                if !remote && model.isLocalLoading { ProgressView().controlSize(.mini) }
                Button { model.createFolder(remote: remote) } label: { Image(systemName: "folder.badge.plus") }.help("新建文件夹").disabled(remote && !model.connected)
                Button { if remote { model.navigateRemote(model.remotePath) } else { model.refreshLocal() } } label: { Image(systemName: "arrow.clockwise") }.help("刷新").disabled(remote && !model.connected)
            }.buttonStyle(SendaIconButtonStyle()).foregroundStyle(T.ink2).padding(.horizontal, T.space(3.5)).padding(.top, T.space(3)).padding(.bottom, T.space(2.5))

            HStack(spacing: T.space(2)) {
                Button {
                    if remote { model.navigateRemote(RemotePath.parent(model.remotePath)) }
                    else { model.navigateLocal((model.localPath as NSString).deletingLastPathComponent) }
                } label: { Image(systemName: "arrow.up").font(.system(size: 11, weight: .semibold)) }
                    .buttonStyle(.plain).disabled(remote && !model.connected).help("上一级目录")
                Divider().frame(height: T.space(3.5))
                if remote {
                    DirectoryPathField(path: model.remotePath, enabled: model.connected, remote: true, onNavigate: model.navigateRemote)
                } else {
                    DirectoryPathField(path: model.localPath, enabled: true, remote: false, onNavigate: model.navigateLocal)
                    Button { model.chooseLocalFolder() } label: { Image(systemName: "ellipsis") }.buttonStyle(.plain).help("选择本地目录")
                }
            }
            .padding(.horizontal, T.space(2.5)).padding(.vertical, T.space(2.25))
            .background(RoundedRectangle(cornerRadius: T.radiusControl).fill(T.inset))
            .overlay(RoundedRectangle(cornerRadius: T.radiusControl).strokeBorder(T.line))
            .padding(.horizontal, T.space(3)).padding(.bottom, T.space(2.5))

            ZStack {
                FileTable(model: model, remote: remote, entries: files)
                if files.isEmpty {
                    VStack(spacing: T.space(3)) {
                        Image(systemName: remote && !model.connected ? "point.3.connected.trianglepath.dotted" : "tray.and.arrow.down")
                            .font(.system(size: 37, weight: .ultraLight)).foregroundStyle(T.ink3)
                        Text(remote && !model.connected ? "连接你的开发机" : "这里还没有文件")
                            .font(.system(size: 15, weight: .medium))
                        Text(remote && !model.connected ? "选择左侧主机，或输入 SSH 别名\nProxyCommand 会自动沿用" : (remote ? "将本地文件拖到这里上传" : "将远程文件拖到这里下载"))
                            .font(.system(size: 11)).foregroundStyle(T.ink2).multilineTextAlignment(.center).lineSpacing(T.space(1))
                    }.padding(.bottom, T.space(7.5)).allowsHitTesting(false)
                }
            }
            SendaRule()
            HStack(spacing: T.space(1.5)) {
                Text(selection.isEmpty ? "\(files.count) 个项目" : "已选择 \(selection.count) 个项目").font(.system(size: 10)).foregroundStyle(T.ink2)
                Button(selection.count == files.count && !files.isEmpty ? "取消选择" : "全选") {
                    if selection.count == files.count { model.deselectAll(remote: remote) }
                    else { model.selectAll(remote: remote) }
                }.buttonStyle(.plain).font(.system(size: 10)).disabled(files.isEmpty)
                    .help("⌘ 点选多个 · ⇧ 连选 · ⌘A 全选 · ⇧⌘A 取消选择")
                Spacer()
                Button { if remote { model.downloadSelection() } else { model.uploadSelection() } } label: {
                    Label(selection.isEmpty ? (remote ? "下载到本地" : "上传到远程") : "\(remote ? "下载" : "上传")所选（\(selection.count)）", systemImage: remote ? "arrow.down" : "arrow.up")
                        .font(.system(size: 11, weight: .medium))
                }.buttonStyle(SendaActionButtonStyle()).disabled(selection.isEmpty || !model.connected)
            }.padding(.horizontal, T.space(3)).padding(.vertical, T.space(2.5))
        }
        .background(SendaTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: T.radiusCard))
        .overlay(RoundedRectangle(cornerRadius: T.radiusCard).strokeBorder(SendaTheme.border))
    }

    private var transfers: some View {
        VStack(spacing: T.space(0)) {
            HStack(spacing: T.space(2)) {
                Image(systemName: "arrow.left.arrow.right").font(.system(size: 11, weight: .medium)).foregroundStyle(sendaAccent)
                Text("传输队列").font(.system(size: 12, weight: .semibold))
                if model.activeJobs > 0 { Text("\(model.activeJobs)").font(.system(size: 10, weight: .medium)).padding(.horizontal, T.space(1.5)).padding(.vertical, T.space(0.5)).background(Capsule().fill(T.accentTint)).foregroundStyle(sendaAccent) }
                Spacer()
                Text("重名自动保留两份").font(.system(size: 10)).foregroundStyle(T.ink3)
                Button("清除已完成") { model.clearFinished() }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(T.ink2).disabled(model.jobs.allSatisfy { $0.state == .waiting || $0.state == .running })
            }.padding(.horizontal, T.space(4)).padding(.vertical, T.space(3))
            SendaRule()
            if model.jobs.isEmpty {
                HStack(spacing: T.space(3.5)) {
                    Image(systemName: "arrow.left.arrow.right").font(.system(size: 23, weight: .ultraLight)).foregroundStyle(T.ink3)
                    VStack(alignment: .leading, spacing: T.space(2)) {
                        Text("文件就绪，随时出发。").font(.system(size: 12, weight: .medium)).foregroundStyle(T.ink2)
                        Text("⌘ 点选多个 · ⇧ 连选 · ⌘A 全选；拖拽所选项目即可批量传输。").font(.system(size: 11)).foregroundStyle(T.ink3)
                    }
                    Spacer()
                }.padding(.horizontal, T.space(6)).frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: T.space(0)) {
                        ForEach(model.jobs) { job in
                            TransferRow(job: job) { model.cancel(job.id) }
                        }
                    }
                }
            }
        }
        .background(SendaTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: T.radiusCard))
        .overlay(RoundedRectangle(cornerRadius: T.radiusCard).strokeBorder(SendaTheme.border))
    }

    private var statusBar: some View {
        HStack(spacing: T.space(2)) {
            Circle().fill(model.connected ? sendaAccent : T.ink3).frame(width: T.space(1.25), height: T.space(1.25))
            Text(model.status).font(.system(size: 10)).foregroundStyle(T.ink2).lineLimit(1)
            Spacer()
            Text("SFTP v3  ·  OpenSSH").font(.system(size: 9, design: .monospaced)).foregroundStyle(T.ink3)
        }.padding(.horizontal, T.space(5)).padding(.vertical, T.space(2.5))
    }

}

private struct DirectoryPathField: View {
    let path: String
    let enabled: Bool
    let remote: Bool
    let onNavigate: (String) -> Void
    @State private var draft = ""
    var body: some View {
        TextField(enabled ? (remote ? "远程目录" : "本地目录") : "等待连接…", text: $draft)
            .textFieldStyle(.plain).font(.system(size: 11, design: .monospaced)).disabled(!enabled)
            .onAppear { draft = path }.onChange(of: path) { draft = $0 }
            .onSubmit { onNavigate(draft) }.accessibilityLabel(remote ? "远程目录路径" : "本地目录路径")
    }
}
