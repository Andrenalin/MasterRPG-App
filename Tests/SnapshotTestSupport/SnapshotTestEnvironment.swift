// @copyright André Trettin

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

    static var baselineVariant: String {
        if let override = SnapshotTestProcessEnvironment.expandedValue(for: environmentKey) {
            return normalizedVariant(override)
        }

        let bundle = Bundle(for: SnapshotTestBundleToken.self)
        guard let encodedVersion = encodedXcodeVersion(in: bundle) else {
            preconditionFailure(
                "The snapshot test bundle does not contain DTXcode. "
                    + "Set \(environmentKey) to an explicit value such as Xcode26 or Xcode27."
            )
        }

        let majorVersion = encodedVersion / 100
        guard majorVersion > 0 else {
            preconditionFailure("Invalid DTXcode value \(encodedVersion) in \(bundle.bundleURL.path()).")
        }
        return "Xcode\(majorVersion)"
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
        return repositoryRoot
            .appending(path: "Snapshots")
            .appending(path: baselineVariant)
            .appending(path: testTargetDirectory.lastPathComponent)
            .appending(path: suiteName)
            .path()
    }

    private static func normalizedVariant(_ value: String) -> String {
        let candidate = value.hasPrefix("Xcode") ? value : "Xcode\(value)"
        let suffix = candidate.dropFirst("Xcode".count)
        let version = suffix.hasSuffix("Recording")
            ? suffix.dropLast("Recording".count)
            : suffix
        guard !version.isEmpty, version.allSatisfy(\.isNumber) else {
            preconditionFailure(
                "\(environmentKey) must be an Xcode major-version folder such as Xcode26 "
                    + "or its Xcode26Recording staging variant; "
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

/// Reads values injected by `SnapshotTests.xctestplan` after Xcode expands its
/// build-setting placeholders. An unset placeholder can arrive either empty or
/// literally as `$(NAME)`, so neither form is treated as a user value.
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

    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.timeZone = timeZone
        return calendar
    }()
}

@MainActor
private struct DeterministicSnapshotEnvironmentModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .environment(\.locale, SnapshotTestEnvironment.locale)
            .environment(\.calendar, SnapshotTestEnvironment.calendar)
            .environment(\.timeZone, SnapshotTestEnvironment.timeZone)
            .environment(\.layoutDirection, .leftToRight)
            .dynamicTypeSize(.large)
            .preferredColorScheme(.light)
            .transaction { transaction in
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
    }
}

extension View {
    /// Fixes host-dependent SwiftUI values before Point-Free renders a view.
    @MainActor
    func deterministicSnapshotEnvironment() -> some View {
        modifier(DeterministicSnapshotEnvironmentModifier())
    }
}
