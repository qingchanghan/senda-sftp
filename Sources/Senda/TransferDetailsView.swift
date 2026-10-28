import AppKit
import SwiftUI

@MainActor
struct TransferDetailsView: View {
    @ObservedObject var job: TransferJob
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: T.space(4)) {
            HStack(alignment: .top, spacing: T.space(2)) {
                VStack(alignment: .leading, spacing: T.space(1.5)) {
                    Text("传输详情").font(.system(size: 18, weight: .semibold))
                    Text(job.name).font(.system(size: 12)).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Text("\(job.uploading ? "上传" : "下载") · \(job.cancellationRequested && job.state == .running ? "取消中…" : job.state.rawValue)")
                    .font(.system(size: 11)).foregroundStyle(T.ink2)
            }
            if job.hasProgress {
                HStack(spacing: T.space(2)) {
                    Text("整体进度").font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text("\(TransferRow.bytes(job.completed)) / \(TransferRow.bytes(job.total))")
                        .font(.system(size: 12, design: .monospaced)).foregroundStyle(T.ink2)
                }
                SendaProgressBar(fraction: job.total == 0 ? (job.state == .done ? 1 : 0) : Double(job.completed) / Double(job.total))
                if job.showsSpeed {
                    HStack(spacing: T.space(2)) {
                        Text(job.uploading ? "上传速度" : "下载速度").font(.system(size: 12, weight: .medium))
                        Spacer()
                        TransferSpeedView(job: job)
                    }
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: T.space(4)) {
                    endpoint("源", machine: job.sourceMachine, pathLabel: "源路径", path: job.sourcePath)
                    endpoint("目标", machine: job.destinationMachine, pathLabel: job.destinationPathLabel, path: job.destinationPath)
                    if job.destinationPath != job.requestedDestinationPath {
                        VStack(alignment: .leading, spacing: T.space(1.5)) {
                            Text("重名自动保留两份，目标路径已更新。")
                            Text("原定目标路径：\(job.requestedDestinationPath)")
                                .font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                        }.font(.system(size: 11)).foregroundStyle(T.ink2)
                    }
                    if !job.error.isEmpty {
                        VStack(alignment: .leading, spacing: T.space(1.5)) {
                            Text(job.state == .cancelled ? "取消信息" : "错误信息").fontWeight(.medium)
                            Text(job.error).textSelection(.enabled)
                        }.font(.system(size: 12)).foregroundStyle(job.state == .cancelled ? T.ink2 : T.red)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            SendaRule()
            HStack(spacing: T.space(2)) {
                Button("复制全部详情") { copy(job.detailsText) }.buttonStyle(SendaActionButtonStyle())
                Spacer()
                Button("关闭") { dismiss() }.buttonStyle(SendaActionButtonStyle(prominent: true)).keyboardShortcut(.cancelAction)
            }
        }.padding(T.space(6)).frame(width: T.space(150), height: T.space(140)).foregroundStyle(T.ink).background(SendaTheme.surface).tint(SendaTheme.accent)
    }

    private func endpoint(_ title: String, machine: String, pathLabel: String, path: String) -> some View {
        VStack(alignment: .leading, spacing: T.space(3)) {
            Text("\(title)机器").font(.system(size: 11)).foregroundStyle(T.ink2)
            Text(machine).font(.system(size: 13, weight: .medium)).textSelection(.enabled)
            HStack(spacing: T.space(2)) {
                Text(pathLabel).font(.system(size: 11)).foregroundStyle(T.ink2)
                Spacer()
                Button { copy(path) } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.plain).help("复制\(title)路径").accessibilityLabel("复制\(title)路径")
            }
            Text(path).font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(T.space(4))
        .background(RoundedRectangle(cornerRadius: T.radiusCard).fill(T.inset))
        .overlay(RoundedRectangle(cornerRadius: T.radiusCard).strokeBorder(T.line))
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
