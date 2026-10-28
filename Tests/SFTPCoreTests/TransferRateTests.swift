import Foundation
import SFTPCore

final class TransferRateTests: CheckCase {
    private func near(_ rate: TransferRate, at time: TimeInterval, _ expected: Double) {
        guard let actual = rate.bytesPerSecond(at: time) else { recordFailure("Missing rate"); return }
        expectTrue(abs(actual - expected) < 0.01)
    }

    func testRecentWindow() {
        var rate = TransferRate()
        expectEqual(rate.bytesPerSecond(at: 0), nil)
        for time in [0.0, 0.3, 0.7, 1.6, 2.6, 3.9] {
            rate.record(completed: UInt64(time * 1000), at: time)
        }
        near(rate, at: 3.9, 1000)
        // Includes cumulative bytes from subsequent files rather than restarting.
        rate.record(completed: 5900, at: 4.9)
        near(rate, at: 4.9, 1500)
    }

    func testStallAndRecovery() {
        var rate = TransferRate()
        rate.record(completed: 0, at: 0)
        rate.record(completed: 1000, at: 1)
        rate.record(completed: 2000, at: 2)
        near(rate, at: 2, 1000)
        near(rate, at: 3, 500)
        near(rate, at: 4, 0)
        near(rate, at: 20, 0)
        rate.record(completed: 2000, at: 20)
        rate.record(completed: 4000, at: 21)
        near(rate, at: 21, 1000)
        rate.record(completed: 6000, at: 22)
        near(rate, at: 22, 2000)
    }

    func testStartupAndProtocolTimestamps() {
        var rate = TransferRate()
        rate.record(completed: 0, at: 100)
        expectEqual(rate.bytesPerSecond(at: 100.1), nil)
        near(rate, at: 100.5, 0)
        rate.record(completed: 2_000_000, at: 102)
        near(rate, at: 102, 1_000_000)
        // Main-thread delivery delayed by a second must not inflate the rate.
        near(rate, at: 103, 500_000)
        expectEqual(rate.bytesPerSecond(at: 101), nil)
    }

    func testStaleAndInvalidSamples() {
        var rate = TransferRate()
        rate.record(completed: 0, at: 10)
        rate.record(completed: 500, at: 10.5)
        rate.record(completed: 900, at: 10.5)
        rate.record(completed: 1000, at: 10.1)
        rate.record(completed: 1, at: 11)
        rate.record(completed: UInt64.max, at: .nan)
        rate.record(completed: UInt64.max, at: .infinity)
        rate.record(completed: UInt64.max, at: -1)
        near(rate, at: 10.5, 1000)
        rate.record(completed: 1000, at: 11)
        near(rate, at: 11, 1000)
        expectEqual(rate.bytesPerSecond(at: .nan), nil)
    }

    func testLargeCounters() {
        var rate = TransferRate()
        rate.record(completed: UInt64.max - 2000, at: 0)
        rate.record(completed: UInt64.max - 1000, at: 1)
        rate.record(completed: UInt64.max, at: 2)
        near(rate, at: 2, 1000)
        near(rate, at: 2.5, 750)
    }

    func testAdaptiveUnits() {
        let fixtures: [(Double, String)] = [
            (0, "0 B/s"), (1, "1 B/s"), (999, "999 B/s"),
            (1000, "1 KB/s"), (1536, "1.5 KB/s"), (999_900, "999.9 KB/s"),
            (999_960, "1 MB/s"), (1_000_000, "1 MB/s"), (24_500_000, "24.5 MB/s"),
            (999_960_000, "1 GB/s"), (1_000_000_000, "1 GB/s"),
            (1_500_000_000, "1.5 GB/s"), (1_000_000_000_000, "1000 GB/s"),
            (-1, "0 B/s"), (.nan, "0 B/s"), (.infinity, "0 B/s")
        ]
        for (bytes, text) in fixtures { expectEqual(TransferRateFormatter.string(bytes), text) }
    }
}
