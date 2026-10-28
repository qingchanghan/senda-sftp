import Foundation

/// Recent throughput from cumulative bytes and monotonic protocol timestamps.
/// The window advances even without new callbacks, so stalled transfers reach zero.
public struct TransferRate: Sendable {
    private struct Sample: Sendable {
        let time: TimeInterval
        let bytes: UInt64
    }
    private var samples: [Sample] = []
    private let window: TimeInterval = 2

    public init() {}

    public mutating func record(completed: UInt64, at time: TimeInterval) {
        guard time.isFinite, time >= 0 else { return }
        if let last = samples.last {
            guard time >= last.time, completed >= last.bytes else { return }
            if time == last.time { return }
        }
        samples.append(Sample(time: time, bytes: completed))
        // Keep the sample bracketing the left edge for interpolation.
        while samples.count > 2 && samples[1].time <= time - window { samples.removeFirst() }
    }

    public func bytesPerSecond(at now: TimeInterval) -> Double? {
        guard now.isFinite, let first = samples.first, let last = samples.last,
              now >= last.time, now - first.time >= 0.25 else { return nil }
        guard now - last.time < window else { return 0 }
        let start = max(first.time, now - window)
        let index = samples.lastIndex(where: { $0.time <= start }) ?? 0
        let before = samples[index]
        var bytes = Double(last.bytes - before.bytes)
        if index + 1 < samples.count {
            let after = samples[index + 1]
            let fraction = (start - before.time) / (after.time - before.time)
            bytes -= Double(after.bytes - before.bytes) * fraction
        }
        return max(0, bytes) / (now - start)
    }
}

public enum TransferRateFormatter {
    /// Decimal units match the file-size column. Cap at GB/s as requested.
    public static func string(_ bytesPerSecond: Double) -> String {
        var value = bytesPerSecond.isFinite ? max(0, bytesPerSecond) : 0
        let units = ["B/s", "KB/s", "MB/s", "GB/s"]
        var unit = 0
        while value >= 1000 && unit < units.count - 1 { value /= 1000; unit += 1 }
        let precision = unit == 0 ? 1.0 : 10.0
        if (value * precision).rounded() / precision >= 1000 && unit < units.count - 1 {
            value /= 1000; unit += 1
        }
        var number = String(format: unit == 0 ? "%.0f" : "%.1f", locale: Locale(identifier: "en_US_POSIX"), value)
        if number.hasSuffix(".0") { number.removeLast(2) }
        return "\(number) \(units[unit])"
    }
}
