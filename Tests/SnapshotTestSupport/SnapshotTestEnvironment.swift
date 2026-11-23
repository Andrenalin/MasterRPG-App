// @copyright André Trettin

#if !os(visionOS)

import CoreRPG
import Foundation
import SnapshotTesting
import SwiftUI
import Testing

private final class SnapshotTestBundleToken: NSObject {}

extension Tag {
    /// Selects repository visual-regression tests from the Snapshot Tests plan.
    @Tag static var snapshot: Self
}

/// Locates the repository-owned snapshot baseline for the active Xcode toolchain.
///
/// SwiftUI pixels can change between Xcode releases even when the source does
/// not. Keeping one tree per major version prevents a developer using a newer
/// toolchain from rewriting another toolchain's reviewed references.
enum SnapshotReferenceLocation {
    private static let environmentKey = "SNAPSHOT_BASELINE_VARIANT"

    static var xcodeMajorVersion: Int {
        let bundle = Bundle(for: SnapshotTestBundleToken.self)
        guard let encodedVersion = encodedXcodeVersion(in: bundle) else {
            preconditionFailure(
                "The snapshot test bundle does not contain DTXcode. "
                    + "Set \(environmentKey) to an explicit value such as Xcode27."
            )
        }

        let majorVersion = encodedVersion / 100
        guard majorVersion > 0 else {
            preconditionFailure("Invalid DTXcode value \(encodedVersion) in \(bundle.bundleURL.path()).")
        }
        return majorVersion
    }

    static var baselineVariant: String {
        if let override = SnapshotTestProcessEnvironment.expandedValue(for: environmentKey) {
            return normalizedVariant(override)
        }
        return "Xcode\(xcodeMajorVersion)"
    }

    static func directory(forTestFile filePath: StaticString) -> String {
        let testFile = URL(filePath: filePath.description)
        let testTargetDirectory = testFile.deletingLastPathComponent()
        let testsDirectory = testTargetDirectory.deletingLastPathComponent()

        guard testsDirectory.lastPathComponent == "Tests" else {
            preconditionFailure(
                "Snapshot test files must be located in Tests/<TestTarget>; received \(testFile.path())."
            )
        }

        let repositoryRoot = testsDirectory.deletingLastPathComponent()
        let suiteName = testFile.deletingPathExtension().lastPathComponent
        let repositoryDirectory = repositoryRoot
            .appending(path: "Snapshots")
            .appending(path: baselineVariant)
            .appending(path: testTargetDirectory.lastPathComponent)
            .appending(path: suiteName)

        // Xcode Cloud builds the test products on one machine and runs them on another
        // that has no repository checkout, so the reviewed references also ship inside the
        // test bundle. The repository copy stays authoritative whenever it exists: local
        // runs and the recording script read and write it.
        if !FileManager.default.fileExists(atPath: repositoryDirectory.path()),
           let bundledDirectory = bundledDirectory(forSuite: suiteName)
        {
            return bundledDirectory.path()
        }
        return repositoryDirectory.path()
    }

    /// The suite's reference folder copied into the test bundle, when the target ships one.
    private static func bundledDirectory(forSuite suiteName: String) -> URL? {
        let bundle = Bundle(for: SnapshotTestBundleToken.self)
        guard let directory = bundle.resourceURL?.appending(path: suiteName, directoryHint: .isDirectory),
              FileManager.default.fileExists(atPath: directory.path())
        else { return nil }
        return directory
    }

    private static func normalizedVariant(_ value: String) -> String {
        let candidate = value.hasPrefix("Xcode") ? value : "Xcode\(value)"
        let suffix = candidate.dropFirst("Xcode".count)
        let version = suffix.hasSuffix("Recording")
            ? suffix.dropLast("Recording".count)
            : suffix
        guard !version.isEmpty, version.allSatisfy(\.isNumber) else {
            preconditionFailure(
                "\(environmentKey) must be an Xcode major-version folder such as Xcode27 "
                    + "or its Xcode27Recording staging variant; "
                    + "received \(value)."
            )
        }
        return candidate
    }

    private static func encodedXcodeVersion(in bundle: Bundle) -> Int? {
        switch bundle.object(forInfoDictionaryKey: "DTXcode") {
        case let value as String:
            return Int(value)
        case let value as NSNumber:
            return value.intValue
        default:
            return nil
        }
    }
}

/// Reads values forwarded to the test runner by the snapshot command-line tool.
private enum SnapshotTestProcessEnvironment {
    static func expandedValue(for key: String) -> String? {
        guard let rawValue = ProcessInfo.processInfo.environment[key] else { return nil }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.hasPrefix("$(") else { return nil }
        return value
    }
}

private enum SnapshotTestRecordingMode {
    private static let environmentKey = "SNAPSHOT_RECORD_MODE"

    static var current: SnapshotTestingConfiguration.Record {
        guard let value = SnapshotTestProcessEnvironment.expandedValue(for: environmentKey) else {
            // Opening the plan in Xcode or invoking it without the recording
            // script must never create or overwrite reviewed references.
            return .never
        }

        guard let mode = SnapshotTestingConfiguration.Record(rawValue: value) else {
            preconditionFailure(
                "\(environmentKey) must be all, failed, missing, or never; received \(value)."
            )
        }
        return mode
    }
}

/// Asserts against the root-level, toolchain-specific reference-image tree.
///
/// Point-Free's public `assertSnapshot` does not expose `snapshotDirectory`.
/// This repository wrapper uses `verifySnapshot` so every suite has one
/// explicit and reviewable baseline location while preserving the caller's
/// Swift Testing source location.
@MainActor
func assertRepositorySnapshot<Value, Format>(
    of value: @autoclosure () throws -> Value,
    as snapshotting: Snapshotting<Value, Format>,
    named name: String? = nil,
    record: SnapshotTestingConfiguration.Record? = nil,
    timeout: TimeInterval = 5,
    fileID: StaticString = #fileID,
    file filePath: StaticString = #filePath,
    testName: String = #function,
    line: UInt = #line,
    column: UInt = #column
) {
    SnapshotTestEnvironment.pinProcessTimeZone()
    let resolvedRecordMode = record ?? SnapshotTestRecordingMode.current
    let failure = verifySnapshot(
        of: try value(),
        as: snapshotting,
        named: name,
        record: resolvedRecordMode,
        snapshotDirectory: SnapshotReferenceLocation.directory(forTestFile: filePath),
        timeout: timeout,
        fileID: fileID,
        file: filePath,
        testName: testName,
        line: line,
        column: column
    )
    guard let failure else { return }

    Issue.record(
        Comment(rawValue: failure),
        sourceLocation: SourceLocation(
            fileID: fileID.description,
            filePath: filePath.description,
            line: Int(line),
            column: Int(column)
        )
    )
}

/// Repository-wide rendering inputs shared by every SwiftUI snapshot suite.
///
/// SnapshotTesting records pixels, so values inherited from the host process
/// must not vary with a developer machine or CI runner. Keep this modifier
/// test-only and apply it after module-specific environment dependencies.
@MainActor
enum SnapshotTestEnvironment {
    static let locale = Locale(identifier: "en_US")

    static let timeZone = TimeZone(secondsFromGMT: 0) ?? .current

    private static var isProcessTimeZonePinned = false

    /// Makes the process default time zone the snapshot time zone, once.
    ///
    /// The `\.timeZone` environment value reaches SwiftUI, but not everything that draws with a
    /// calendar: the Charts framework puts its month gridlines and axis labels where midnight
    /// falls in the process time zone, so the same chart moved by a few pixels between a
    /// developer machine (UTC+7, where the references were recorded) and Xcode Cloud (US
    /// Pacific): `GameStatisticsActivityChart` matched 0.9958 of its pixels there and
    /// `GameStatisticsPreviewDashboardView` 0.8811, exactly what `TEST_RUNNER_TZ=America/Los_Angeles`
    /// reproduces locally.
    static func pinProcessTimeZone() {
        guard !isProcessTimeZonePinned else { return }
        isProcessTimeZonePinned = true
        // `TZ` is what the system time zone is read from; the caches are reset so a zone that
        // was already read (`Calendar.current`, `TimeZone.current`) is read again.
        setenv("TZ", timeZone.identifier, 1)
        tzset()
        NSTimeZone.resetSystemTimeZone()
        NSTimeZone.default = timeZone
    }

    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.timeZone = timeZone
        return calendar
    }()
}

@MainActor
private struct DeterministicSnapshotEnvironmentModifier: ViewModifier {
    let dynamicTypeSize: DynamicTypeSize

    func body(content: Content) -> some View {
        content
            .environment(\.locale, SnapshotTestEnvironment.locale)
            .environment(\.calendar, SnapshotTestEnvironment.calendar)
            .environment(\.timeZone, SnapshotTestEnvironment.timeZone)
            .environment(\.layoutDirection, .leftToRight)
            .environment(\.isSnapshotRendering, true)
            .dynamicTypeSize(dynamicTypeSize)
            .preferredColorScheme(.light)
            .transaction { transaction in
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
    }
}

extension View {
    /// Fixes host-dependent SwiftUI values before Point-Free renders a view.
    ///
    /// `dynamicTypeSize` is `.large` for the reviewed baseline. The accessibility suites pass a
    /// larger size to check the layout of the same views at an accessibility text size.
    @MainActor
    func deterministicSnapshotEnvironment(dynamicTypeSize: DynamicTypeSize = .large) -> some View {
        modifier(DeterministicSnapshotEnvironmentModifier(dynamicTypeSize: dynamicTypeSize))
    }
}

/// Owns the `@FocusState` a view under test takes as a binding.
///
/// A `@FocusState` declared as a local variable of a test function is read outside a view body,
/// which SwiftUI reports ("Accessing FocusState's value outside of the body of a View") and answers
/// with a constant binding. Declared here it is installed on a real view.
struct OptionalFocusStateHarness<Value: Hashable, Content: View>: View {
    @FocusState private var focusedValue: Value?
    private let content: (FocusState<Value?>.Binding) -> Content

    init(@ViewBuilder content: @escaping (FocusState<Value?>.Binding) -> Content) {
        self.content = content
    }

    var body: some View {
        content($focusedValue)
    }
}

#endif
