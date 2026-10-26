import AppKit
import SwiftUI
import SFTPCore

/// Beautiful UI SidebarNav, adapted to native SSH host navigation.
struct HostSidebar: View {
    @ObservedObject var model: AppModel
    @State private var search = ""
    private var hosts: [SSHHost] {
        search.isEmpty ? model.hosts : model.hosts.filter { $0.alias.localizedCaseInsensitiveContains(search) || $0.user.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: T.space(0)) {
            HStack(spacing: T.space(2.5)) {
                Image(systemName: "arrow.up.right.and.arrow.down.left")
                    .font(.system(size: 18, weight: .semibold)).foregroundStyle(T.page)
                    .frame(width: T.space(9), height: T.space(9))
                    .background(RoundedRectangle(cornerRadius: T.radiusCard).fill(T.ink))
                VStack(alignment: .leading, spacing: T.space(0.5)) {
                    Text("Senda").font(.system(size: 24, weight: .semibold, design: .rounded))
                    Text("A path for your files.").font(.system(size: 10)).foregroundStyle(T.ink2)
                }
            }.padding(.top, T.space(10)).padding(.horizontal, T.space(5)).padding(.bottom, T.space(7))

            HStack(spacing: T.space(2)) {
                Text("开发机").font(.system(size: 11, weight: .medium))
                Text("\(model.hosts.count)").font(.system(size: 10, design: .monospaced))
                Spacer()
                Button { model.refreshHosts() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).frame(width: T.space(7), height: T.space(7)).help("重新读取 ~/.ssh/config")
            }.foregroundStyle(T.ink2).padding(.horizontal, T.space(5))

            HStack(spacing: T.space(1.5)) {
                Image(systemName: "magnifyingglass").font(.system(size: 11))
                TextField("查找主机", text: $search).textFieldStyle(.plain).font(.system(size: 12))
                    .accessibilityLabel("查找 SSH 主机")
            }.foregroundStyle(T.ink2).padding(T.space(2))
                .background(RoundedRectangle(cornerRadius: T.radiusControl).fill(T.field))
                .padding(.horizontal, T.space(4)).padding(.bottom, T.space(3))

            HostSidebarScrollView {
                VStack(spacing: T.space(1)) {
                    ForEach(hosts) { host in
                        HostSidebarRow(host: host, active: model.connectedHost == host.alias,
                                       connecting: model.isConnecting && model.hostInput == host.alias) { model.connect(host.alias) }
                    }
                    if hosts.isEmpty {
                        Text(search.isEmpty ? "在 ~/.ssh/config 添加主机，\n或输入 SSH 别名连接。" : "没有匹配的主机")
                            .font(.system(size: 11)).foregroundStyle(T.ink2).lineSpacing(T.space(1)).padding(T.space(3))
                    }
                }.padding(.horizontal, T.space(2)).padding(.vertical, T.space(1))
            }

            VStack(alignment: .leading, spacing: T.space(3)) {
                SendaRule()
                HStack(spacing: T.space(2)) {
                    Image(systemName: "lock.shield").foregroundStyle(model.connected ? T.green : T.ink3)
                    VStack(alignment: .leading, spacing: T.space(1)) {
                        Text("系统 OpenSSH").font(.system(size: 11, weight: .medium))
                        Text("沿用你的 SSH 配置与代理").font(.system(size: 10)).foregroundStyle(T.ink2)
                    }
                }
                HStack(spacing: T.space(2)) {
                    Text("SENDA").tracking(2)
                    Spacer()
                    Text("v1.5.0")
                }.font(.system(size: 9, design: .monospaced)).foregroundStyle(T.ink3)
            }.padding(T.space(5))
        }
        .foregroundStyle(T.ink).background(T.page)
        .overlay(alignment: .trailing) { Rectangle().fill(T.line).frame(width: T.space(0.25)) }
    }
}

private struct HostSidebarRow: View {
    let host: SSHHost
    let active: Bool
    let connecting: Bool
    let connect: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: connect) {
            HStack(spacing: T.space(2)) {
                Image(systemName: "server.rack").font(.system(size: 15))
                    .foregroundStyle(active ? T.accentInk : T.ink2).frame(width: T.space(6))
                VStack(alignment: .leading, spacing: T.space(1)) {
                    Text(host.alias).font(.system(size: 12, weight: active ? .semibold : .medium)).lineLimit(1)
                    Text(host.user.isEmpty ? "SSH 主机" : host.user).font(.system(size: 10)).foregroundStyle(T.ink2).lineLimit(1)
                }
                Spacer(minLength: T.space(1))
                if connecting { ProgressView().controlSize(.mini) }
                else if active { Circle().fill(T.green).frame(width: T.space(1.5), height: T.space(1.5)) }
                else if host.usesProxy { Image(systemName: "point.3.connected.trianglepath.dotted").font(.system(size: 11)).foregroundStyle(T.ink3) }
            }.padding(.horizontal, T.space(3)).padding(.vertical, T.space(2.5))
                .background(RoundedRectangle(cornerRadius: T.radiusControl).fill(active ? T.accentTint : (hovering ? T.hover2 : T.page)))
                .contentShape(RoundedRectangle(cornerRadius: T.radiusControl))
        }.buttonStyle(.plain).foregroundStyle(T.ink).onHover { hovering = $0 }
            .help([host.alias, host.hostname, host.usesProxy ? "通过 SSH 代理连接" : ""].filter { !$0.isEmpty }.joined(separator: " · "))
    }
}

/// Keep both overlay and "always visible" macOS scrollbars free of an opaque gutter.
struct HostSidebarScrollView<Content: View>: NSViewRepresentable {
    let content: Content
    @Environment(\.colorScheme) private var scheme
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.identifier = .init("hosts-scroll"); scroll.setAccessibilityLabel("开发机列表")
        scroll.drawsBackground = false; scroll.contentView.drawsBackground = false
        scroll.borderType = .noBorder; scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = false
        scroll.verticalScroller = SidebarScroller(); scroll.scrollerStyle = .overlay; scroll.autohidesScrollers = true
        let hosting = NSHostingView(rootView: AnyView(content.environment(\.colorScheme, scheme)))
        hosting.translatesAutoresizingMaskIntoConstraints = false; scroll.documentView = hosting
        hosting.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let hosting = scroll.documentView as? NSHostingView<AnyView> else { return }
        hosting.rootView = AnyView(content.environment(\.colorScheme, scheme))
    }
}

private final class SidebarScroller: NSScroller {
    override class var isCompatibleWithOverlayScrollers: Bool { true }
    override var isOpaque: Bool { false }
    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}
    override func drawKnob() {
        let slot = rect(for: .knob)
        let knob = NSRect(x: slot.midX - T.space(0.75), y: slot.minY + T.space(0.5), width: T.space(1.5), height: max(0, slot.height - T.space(1)))
        T.ink3NS.setFill()
        NSBezierPath(roundedRect: knob, xRadius: T.space(0.75), yRadius: T.space(0.75)).fill()
    }
}
