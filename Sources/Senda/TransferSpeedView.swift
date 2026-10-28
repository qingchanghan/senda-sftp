import SwiftUI

/// A small, independently ticking label within Beautiful UI's transfer metadata.
@MainActor
struct TransferSpeedView: View {
    @ObservedObject var job: TransferJob

    var body: some View {
        if job.showsSpeed {
            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                let speed = job.speedText() ?? "测速中…"
                Text(speed)
                    .font(.system(size: 10, design: .monospaced)).monospacedDigit()
                    .foregroundStyle(T.ink2)
                    .accessibilityLabel("\(job.uploading ? "上传" : "下载")速度，\(speed)")
            }.help(job.uploading ? "实时上传速度" : "实时下载速度")
        }
    }
}
