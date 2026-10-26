import Foundation
import SFTPCore

// A standalone runner keeps checks runnable with Apple's Command Line Tools alone.
// XCTest/Swift Testing ship with full Xcode, which is intentionally not required.
private let checkLock = NSLock()
private var failureCount = 0

func recordFailure(_ message: String, file: StaticString = #filePath, line: UInt = #line) {
    checkLock.lock(); failureCount += 1; checkLock.unlock()
    fputs("  FAIL \(file):\(line): \(message)\n", stderr)
}

func expectEqual<T: Equatable>(_ left: @autoclosure () throws -> T, _ right: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) {
    do { let a = try left(), b = try right(); if a != b { recordFailure("\(a) != \(b)", file: file, line: line) } }
    catch { recordFailure(error.localizedDescription, file: file, line: line) }
}
func expectNotEqual<T: Equatable>(_ left: @autoclosure () throws -> T, _ right: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) {
    do { if try left() == right() { recordFailure("Expected unequal values", file: file, line: line) } }
    catch { recordFailure(error.localizedDescription, file: file, line: line) }
}
func expectTrue(_ value: @autoclosure () throws -> Bool, file: StaticString = #filePath, line: UInt = #line) {
    do { if try !value() { recordFailure("Expected true", file: file, line: line) } }
    catch { recordFailure(error.localizedDescription, file: file, line: line) }
}
func expectFalse(_ value: @autoclosure () throws -> Bool, file: StaticString = #filePath, line: UInt = #line) {
    do { if try value() { recordFailure("Expected false", file: file, line: line) } }
    catch { recordFailure(error.localizedDescription, file: file, line: line) }
}
func expectThrows<T>(_ value: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) {
    do { _ = try value(); recordFailure("Expected an error", file: file, line: line) } catch {}
}

struct CheckSkip: Error { let reason: String; init(_ reason: String) { self.reason = reason } }
final class CheckExpectation {
    let semaphore = DispatchSemaphore(value: 0)
    func fulfill() { semaphore.signal() }
}
class CheckCase {
    func setUpWithError() throws {}
    func tearDownWithError() throws {}
    func expectation(description: String) -> CheckExpectation { CheckExpectation() }
    func wait(for expectations: [CheckExpectation], timeout: TimeInterval) {
        for expectation in expectations where expectation.semaphore.wait(timeout: .now() + timeout) == .timedOut { recordFailure("Timed out") }
    }
}

@main
struct CheckRunner {
    static func main() {
        let config = ConfigurationTests(), sftp = SFTPIntegrationTests(), remote = RemoteSmokeTests()
        var checks: [(String, CheckCase, () throws -> Void)] = [
            ("SSH aliases and proxy discovery", config, config.testConcreteAliasesAndProxyDiscovery),
            ("SSH includes and cycles", config, config.testIncludesAvoidCycles),
            ("Path safety and option injection", config, config.testSafeNamesAndPaths),
            ("Packet boundaries and Unicode", config, config.testBinaryPacketBounds),
            ("Directory operations and special filenames", sftp, sftp.testDirectoryAndSpecialNames),
            ("Binary round trip and collision protection", sftp, sftp.testBinaryRoundTripAndCollisionProtection),
            ("Recursive folders, empty files and symlinks", sftp, sftp.testEmptyFileAndRecursiveFoldersSkipSymlinks),
            ("Whole-directory upload/download progress", sftp, sftp.testWholeDirectoryProgress),
            ("Empty-directory progress and cancelled scan", sftp, sftp.testEmptyDirectoryProgressAndCancelledScan),
            ("Cancellation and partial-file cleanup", sftp, sftp.testCancellationCleansPartialFiles),
            ("Existing file preservation", sftp, sftp.testPermissionErrorDoesNotReplaceTarget),
            ("Interrupt blocked connection", sftp, sftp.testStopInterruptsBlockedConnection),
            ("Cancelled listing preserves the connection", sftp, sftp.testCancelledListingKeepsConnectionUsable)
        ]
        if ProcessInfo.processInfo.environment["SENDA_TEST_SSH_HOST"] != nil {
            checks = [("Remote SSH ProxyCommand round trip", remote, remote.testConfiguredSSHProxyRoundTrip)]
        }
        for (name, suite, operation) in checks {
            print("CHECK \(name)"); fflush(stdout)
            let before = failureCount
            do { try suite.setUpWithError(); try operation() }
            catch let skip as CheckSkip { print("  SKIP \(skip.reason)") }
            catch { recordFailure(error.localizedDescription) }
            do { try suite.tearDownWithError() } catch { recordFailure(error.localizedDescription) }
            if failureCount == before { print("  PASS") }
            fflush(stdout)
        }
        print("\n\(checks.count) checks, \(failureCount) failures")
        exit(failureCount == 0 ? 0 : 1)
    }
}
