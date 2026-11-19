// @copyright André Trettin

import Foundation
import Testing

@testable import SpaceRPG

/// CODE_AUDIT_TestGaps §5.10: the capture pipeline parts that need no camera, the onboarding
/// transition table and the capture folder. (The stale-scan cleanup has its own suite.)
@MainActor
@Suite("Capture onboarding state machine")
struct OnboardingStateMachineTests {
    private static let anyContinue: [OnboardingUserInput] = [.continue(isFlippable: true), .continue(isFlippable: false)]

    private func machine(in state: OnboardingState) -> OnboardingStateMachine {
        OnboardingStateMachine(state)
    }

    private static let everyInput: [OnboardingUserInput] = anyContinue + [
        .skip(isFlippable: true), .skip(isFlippable: false), .finish, .objectCannotBeFlipped, .flipObjectAnyway
    ]

    private static let initialStates: [OnboardingState] = [
        .tooFewImages, .firstSegmentNeedsWork, .firstSegmentComplete,
        .secondSegmentNeedsWork, .secondSegmentComplete, .thirdSegmentNeedsWork, .thirdSegmentComplete
    ]

    /// A machine that stands in `state`, reached the way the app reaches it: from a review result
    /// through real transitions (a breadth-first search over the machine's own `enter`). Only the
    /// review results can be created directly.
    private func machine(reaching state: OnboardingState) -> OnboardingStateMachine? {
        var seen = Set<OnboardingState>()
        var queue: [(start: OnboardingState, path: [OnboardingUserInput], state: OnboardingState)] =
            Self.initialStates.map { ($0, [], $0) }
        while !queue.isEmpty {
            let entry = queue.removeFirst()
            guard seen.insert(entry.state).inserted else { continue }
            if entry.state == state {
                let machine = OnboardingStateMachine(entry.start)
                for input in entry.path { _ = machine.enter(input) }
                return machine
            }
            for input in Self.everyInput {
                let probe = OnboardingStateMachine(entry.start)
                var ok = true
                for step in entry.path { ok = ok && probe.enter(step) }
                guard ok, probe.enter(input) else { continue }
                queue.append((entry.start, entry.path + [input], probe.currentState))
            }
        }
        return nil
    }

    // MARK: - Initial state

    @Test("It starts at the first segment, and an invalid initial state falls back to it")
    func initialState() {
        #expect(OnboardingStateMachine().currentState == .firstSegment)
        // `.dismiss` and `.reconstruction` are end states, never entered from outside.
        #expect(OnboardingStateMachine(.dismiss).currentState == .firstSegment)
        #expect(OnboardingStateMachine(.reconstruction).currentState == .firstSegment)
        #expect(OnboardingStateMachine(.flipObject).currentState == .firstSegment)
    }

    @Test("Each review result is an allowed initial state", arguments: [
        OnboardingState.tooFewImages, .firstSegmentNeedsWork, .firstSegmentComplete,
        .secondSegmentNeedsWork, .secondSegmentComplete, .thirdSegmentNeedsWork, .thirdSegmentComplete
    ])
    func reviewResultsAreInitialStates(state: OnboardingState) {
        #expect(OnboardingStateMachine(state).currentState == state)
    }

    @Test("reset only accepts an initial state and keeps the state otherwise")
    func resetValidatesTheState() {
        let machine = machine(in: .firstSegmentNeedsWork)

        #expect(machine.reset(to: .secondSegmentComplete))
        #expect(machine.currentState == .secondSegmentComplete)
        #expect(!machine.reset(to: .flipObject))
        #expect(machine.currentState == .secondSegmentComplete)
    }

    // MARK: - Transition table

    @Test("Every transition goes where the table says", arguments: [
        (OnboardingState.tooFewImages, OnboardingUserInput.continue(isFlippable: true), OnboardingState.firstSegment),
        (.tooFewImages, .continue(isFlippable: false), .firstSegment),
        (.firstSegmentNeedsWork, .continue(isFlippable: true), .firstSegment),
        (.firstSegmentNeedsWork, .skip(isFlippable: true), .flipObject),
        (.firstSegmentNeedsWork, .skip(isFlippable: false), .flipObject),
        (.firstSegmentComplete, .finish, .reconstruction),
        (.firstSegmentComplete, .continue(isFlippable: true), .flipObject),
        (.firstSegmentComplete, .continue(isFlippable: false), .flippingObjectNotRecommended),
        (.flipObject, .continue(isFlippable: true), .secondSegment),
        (.flipObject, .continue(isFlippable: false), .secondSegment),
        (.flipObject, .objectCannotBeFlipped, .captureFromLowerAngle),
        (.flippingObjectNotRecommended, .continue(isFlippable: false), .captureFromLowerAngle),
        (.flippingObjectNotRecommended, .flipObjectAnyway, .flipObject),
        (.captureFromLowerAngle, .finish, .reconstruction),
        (.captureFromLowerAngle, .continue(isFlippable: true), .additionalOrbitOnCurrentSegment),
        (.secondSegmentNeedsWork, .continue(isFlippable: false), .dismiss),
        (.secondSegmentNeedsWork, .skip(isFlippable: true), .flipObjectASecondTime),
        (.secondSegmentNeedsWork, .skip(isFlippable: false), .captureFromHigherAngle),
        (.secondSegmentComplete, .continue(isFlippable: true), .flipObjectASecondTime),
        (.secondSegmentComplete, .continue(isFlippable: false), .captureFromHigherAngle),
        (.flipObjectASecondTime, .finish, .reconstruction),
        (.flipObjectASecondTime, .continue(isFlippable: true), .thirdSegment),
        (.captureFromHigherAngle, .finish, .reconstruction),
        (.captureFromHigherAngle, .continue(isFlippable: false), .additionalOrbitOnCurrentSegment),
        (.thirdSegmentNeedsWork, .finish, .reconstruction),
        (.thirdSegmentNeedsWork, .continue(isFlippable: true), .dismiss),
        (.thirdSegmentComplete, .finish, .reconstruction)
    ])
    func transitions(from: OnboardingState, input: OnboardingUserInput, to: OnboardingState) {
        guard let machine = machine(reaching: from) else {
            Issue.record("\(from) cannot be reached from any review result")
            return
        }
        #expect(machine.currentState == from)

        #expect(machine.enter(input))
        #expect(machine.currentState == to)
    }

    @Test("An input the state does not offer changes nothing", arguments: [
        (OnboardingState.thirdSegmentComplete, OnboardingUserInput.continue(isFlippable: true)),
        (.thirdSegmentComplete, .skip(isFlippable: true)),
        (.tooFewImages, .finish),
        (.firstSegmentComplete, .skip(isFlippable: true)),
        (.firstSegmentComplete, .objectCannotBeFlipped),
        (.secondSegmentComplete, .finish),
        (.firstSegmentComplete, .flipObjectAnyway)
    ])
    func unknownInputIsRefused(state: OnboardingState, input: OnboardingUserInput) {
        let machine = machine(in: state)

        #expect(!machine.enter(input))
        #expect(machine.currentState == state)
    }

    @Test("A state without transitions refuses every input")
    func endStateHasNoTransitions() {
        let machine = machine(in: .firstSegmentComplete)
        #expect(machine.enter(.finish))
        #expect(machine.currentState == .reconstruction)

        #expect(!machine.enter(.finish))
        #expect(!machine.enter(.continue(isFlippable: true)))
        #expect(machine.currentState == .reconstruction)
        #expect(machine.currentStateInputs().isEmpty)
    }

    @Test("A capture that cannot be flipped walks from the first segment to the end")
    func pathWithoutFlipping() {
        let machine = machine(in: .firstSegmentComplete)

        #expect(machine.enter(.continue(isFlippable: false)))
        #expect(machine.currentState == .flippingObjectNotRecommended)
        #expect(machine.enter(.continue(isFlippable: false)))
        #expect(machine.currentState == .captureFromLowerAngle)
        #expect(machine.enter(.continue(isFlippable: false)))
        #expect(machine.currentState == .additionalOrbitOnCurrentSegment)
        #expect(machine.enter(.finish) == false, "the additional orbit is a capture state with no review transitions")
    }

    @Test("A flippable capture walks through three segments to the reconstruction")
    func pathWithFlipping() {
        let machine = machine(in: .firstSegmentComplete)

        #expect(machine.enter(.continue(isFlippable: true)))
        #expect(machine.currentState == .flipObject)
        #expect(machine.enter(.continue(isFlippable: true)))
        #expect(machine.currentState == .secondSegment)
        #expect(machine.reset(to: .secondSegmentComplete))
        #expect(machine.enter(.continue(isFlippable: true)))
        #expect(machine.currentState == .flipObjectASecondTime)
        #expect(machine.enter(.continue(isFlippable: true)))
        #expect(machine.currentState == .thirdSegment)
        #expect(machine.reset(to: .thirdSegmentComplete))
        #expect(machine.enter(.finish))
        #expect(machine.currentState == .reconstruction)
    }

    @Test("The offered inputs of a state are the inputs of its transitions")
    func offeredInputs() {
        #expect(machine(in: .firstSegmentComplete).currentStateInputs() == [
            .finish, .continue(isFlippable: true), .continue(isFlippable: false)
        ])
        #expect(machine(in: .thirdSegmentComplete).currentStateInputs() == [.finish])
        #expect(machine(in: .firstSegmentNeedsWork).currentStateInputs() == Self.anyContinue + [.skip(isFlippable: true), .skip(isFlippable: false)])
    }

    @Test("Every state of the flow can be reached from a review result")
    func everyStateIsReachable() {
        let reachable: [OnboardingState] = [
            .firstSegment, .secondSegment, .thirdSegment, .flipObject, .flipObjectASecondTime,
            .flippingObjectNotRecommended, .captureFromLowerAngle, .captureFromHigherAngle,
            .additionalOrbitOnCurrentSegment, .dismiss, .reconstruction
        ]
        for state in reachable {
            #expect(machine(reaching: state) != nil, "\(state) is unreachable")
        }
    }

    @Test("Every state with a transition leads to a state that is known")
    func tableIsClosed() {
        // Walk every initial state with every input; whatever it reaches must be either an end
        // state or a state that itself offers inputs or is a capture state.
        let inputs = Self.everyInput
        let starts = Self.initialStates
        let captureStates: Set<OnboardingState> = [
            .firstSegment, .secondSegment, .thirdSegment, .additionalOrbitOnCurrentSegment, .dismiss, .reconstruction
        ]
        for start in starts {
            for input in inputs {
                let machine = machine(in: start)
                guard machine.enter(input) else { continue }
                let reached = machine.currentState
                #expect(captureStates.contains(reached) || !machine.currentStateInputs().isEmpty,
                        "\(start) + \(input) reaches \(reached), which offers nothing and is not an end or capture state")
            }
        }
    }
}

@MainActor
@Suite("Capture folder manager")
struct CaptureFolderManagerTests {
    private func url(_ name: String) -> URL {
        URL(filePath: "/tmp/Scans/x/Images/\(name)")
    }

    // MARK: - Shot ids

    @Test("The shot id is the number after IMG_", arguments: [
        ("IMG_0001.HEIC", UInt32(1)),
        ("IMG_0042.HEIC", 42),
        ("IMG_4294967295.HEIC", UInt32.max),
        ("IMG_0.heic", 0)
    ])
    func parsesShotIds(name: String, expected: UInt32) {
        #expect(CaptureFolderManager.parseShotId(url: url(name)) == expected)
    }

    @Test("A file that is not a shot of the sample has no id", arguments: [
        "photo.HEIC",
        "IMG0001.HEIC",
        "PIC_0001.HEIC",
        "IMG_.HEIC",
        "IMG_abc.HEIC",
        "IMG_-1.HEIC",
        "IMG_4294967296.HEIC",
        "IMG_1_2.HEIC"
    ])
    func rejectsForeignFiles(name: String) {
        #expect(CaptureFolderManager.parseShotId(url: url(name)) == nil)
    }

    // MARK: - Folder

    @Test("A new capture folder has the three subfolders, below Scans in the caches")
    func createsTheSubfolders() throws {
        let manager = try #require(CaptureFolderManager())
        defer { try? FileManager.default.removeItem(at: manager.rootScanFolder) }

        for folder in [manager.imagesFolder, manager.snapshotsFolder, manager.modelsFolder] {
            var isDirectory: ObjCBool = false
            #expect(FileManager.default.fileExists(atPath: folder.path(percentEncoded: false), isDirectory: &isDirectory))
            #expect(isDirectory.boolValue)
            #expect(folder.path(percentEncoded: false).hasPrefix(manager.rootScanFolder.path(percentEncoded: false)))
        }
        #expect(manager.rootScanFolder.path(percentEncoded: false).contains("/Scans/"))
        #expect(manager.rootScanFolder.path(percentEncoded: false).hasPrefix(URL.cachesDirectory.path(percentEncoded: false)),
                "raw capture photos must not be in the documents folder (CODE_AUDIT_Space §6.1)")
    }

    @Test("Two scans started in the same second get different folders")
    func scansDoNotShareAFolder() throws {
        let first = try #require(CaptureFolderManager())
        let second = try #require(CaptureFolderManager())
        defer {
            try? FileManager.default.removeItem(at: first.rootScanFolder)
            try? FileManager.default.removeItem(at: second.rootScanFolder)
        }

        #expect(first.rootScanFolder != second.rootScanFolder)
    }

    @Test("Loading the shots lists the HEIC images sorted by id and skips the rest")
    func loadsShotsSortedAndFiltered() async throws {
        let manager = try #require(CaptureFolderManager())
        defer { try? FileManager.default.removeItem(at: manager.rootScanFolder) }
        for name in ["IMG_0010.HEIC", "IMG_0002.HEIC", "IMG_0001.HEIC", "IMG_0003.png", "notes.txt", "IMG_x.HEIC", ".IMG_0099.HEIC"] {
            try Data([1]).write(to: manager.imagesFolder.appending(path: name))
        }

        try await manager.loadShots()

        #expect(manager.shots.map(\.id) == [1, 2, 10])
        #expect(manager.shots.map(\.fileUrl.lastPathComponent) == ["IMG_0001.HEIC", "IMG_0002.HEIC", "IMG_0010.HEIC"])
    }

    @Test("Loading the shots of an empty folder gives none, and reloading replaces the list")
    func reloadReplacesTheList() async throws {
        let manager = try #require(CaptureFolderManager())
        defer { try? FileManager.default.removeItem(at: manager.rootScanFolder) }

        try await manager.loadShots()
        #expect(manager.shots.isEmpty)

        let shot = manager.imagesFolder.appending(path: "IMG_0005.HEIC")
        try Data([1]).write(to: shot)
        try await manager.loadShots()
        #expect(manager.shots.map(\.id) == [5])

        try FileManager.default.removeItem(at: shot)
        try await manager.loadShots()
        #expect(manager.shots.isEmpty)
    }

    @Test("Loading the shots fails when the images folder is gone and keeps the old list")
    func missingImagesFolderThrows() async throws {
        let manager = try #require(CaptureFolderManager())
        defer { try? FileManager.default.removeItem(at: manager.rootScanFolder) }
        try Data([1]).write(to: manager.imagesFolder.appending(path: "IMG_0001.HEIC"))
        try await manager.loadShots()
        try FileManager.default.removeItem(at: manager.imagesFolder)

        await #expect(throws: (any Error).self) { try await manager.loadShots() }
        #expect(manager.shots.map(\.id) == [1])
    }

    @Test("A cleanup that starts before a new capture leaves that capture alone")
    func cleanupKeepsALiveScan() async throws {
        let cutoff = Date.now.addingTimeInterval(-3_600)
        let manager = try #require(CaptureFolderManager())
        defer { try? FileManager.default.removeItem(at: manager.rootScanFolder) }
        try Data([1]).write(to: manager.imagesFolder.appending(path: "IMG_0001.HEIC"))

        CaptureFolderManager.cleanupStaleScans(createdBefore: cutoff)

        #expect(FileManager.default.fileExists(atPath: manager.imagesFolder.appending(path: "IMG_0001.HEIC").path(percentEncoded: false)))
    }
}
