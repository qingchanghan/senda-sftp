import SwiftUI

/// Beautiful UI TaskRows: status ring, amount/speed column, semantic capsule, detail action.
@MainActor
struct TransferRow: View {
    @ObservedObject var job: TransferJob
    let onCancel: () -> Void
    @State private var showingDetails = false
    private var fraction: Double { job.total > 0 ? min(1, Double(job.completed) / Double(job.total)) : (job.state == .done ? 1 : 0) }
    private var label: String {
        if job.cancellationRequested && job.state == .running { return "取消中…" }
        if job.state == .running && !job.hasProgress { return "计算大小" }
        return job.state.rawValue
    }
    private var color: Color { job.state == .failed ? T.red : (job.state == .done ? T.green : T.accentInk) }
    private var tint: Color { job.state == .failed ? T.redTint : (job.state == .done ? T.greenTint : T.accentTint) }
    var body: some View {
        HStack(spacing: T.space(3)) {
            ZStack {
                Circle().stroke(T.lineStrong, lineWidth: T.space(0.5))
                if job.state == .running || job.state == .done {
                    Circle().trim(from: 0, to: fraction).stroke(color, style: StrokeStyle(lineWidth: T.space(0.5), lineCap: .round)).rotationEffect(.degrees(-90))
                }
                Image(systemName: job.state == .done ? "checkmark" : (job.uploading ? "arrow.up.right" : "arrow.down.left"))
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(color)
            }.frame(width: T.space(8), height: T.space(8)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: T.space(1.5)) {
                Text(job.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                HStack(spacing: T.space(1.5)) {
                    Text(job.uploading ? "我的 Mac" : job.host)
                    Image(systemName: "arrow.right").font(.system(size: 8))
                    Text(job.uploading ? job.host : "我的 Mac")
                }.font(.system(size: 10)).foregroundStyle(T.ink2)
                if !job.error.isEmpty { Text(job.error).font(.system(size: 10)).foregroundStyle(T.red).lineLimit(1).help(job.error) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if job.hasProgress {
                VStack(alignment: .trailing, spacing: T.space(1.5)) {
                    VStack(alignment: .trailing, spacing: T.space(1.5)) {
                        HStack(spacing: T.space(2)) {
                            Text("\(Self.bytes(job.completed)) / \(Self.bytes(job.total))").foregroundStyle(T.ink2)
                            Text("\(Int(fraction * 100))%").foregroundStyle(T.ink)
                        }.font(.system(size: 10, design: .monospaced)).monospacedDigit()
                        SendaProgressBar(fraction: fraction, color: color)
                    }.accessibilityElement(children: .ignore)
                        .accessibilityLabel("整体进度 \(Int(fraction * 100))%，\(Self.bytes(job.completed)) / \(Self.bytes(job.total))")
                    TransferSpeedView(job: job)
                }.frame(width: T.space(50))
            } else if job.state == .running {
                ProgressView().controlSize(.small).frame(width: T.space(7))
            }
            SendaBadge(title: label, foreground: color, background: tint).frame(width: T.space(18))
            Button("详情") { showingDetails = true }.buttonStyle(SendaActionButtonStyle()).font(.system(size: 11))
                .accessibilityLabel("查看 \(job.name) 的传输详情")
            if job.state == .waiting || job.state == .running {
                Button(action: onCancel) { Image(systemName: "xmark").font(.system(size: 10)) }
                    .buttonStyle(SendaIconButtonStyle()).help("取消传输").accessibilityLabel("取消 \(job.name) 的传输")
            } else { Color.clear.frame(width: T.space(7)) }
        }.foregroundStyle(T.ink).padding(.horizontal, T.space(4)).padding(.vertical, T.space(3))
            .overlay(alignment: .bottom) { SendaRule().padding(.horizontal, T.space(4)) }
            .sheet(isPresented: $showingDetails) { TransferDetailsView(job: job) }
    }
    private static let formatter: ByteCountFormatter = { let value = ByteCountFormatter(); value.countStyle = .file; return value }()
    static func bytes(_ count: UInt64) -> String { formatter.string(fromByteCount: Int64(clamping: count)) }
}
