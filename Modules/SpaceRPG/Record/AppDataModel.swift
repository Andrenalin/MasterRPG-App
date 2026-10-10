/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A data model that maintains the state of the app.
*/

#if os(iOS) && !targetEnvironment(simulator)

import CoreRPG
import RealityKit
import SwiftUI
import os

enum ConfigCaptureObject {
    static func isSupported() async -> Bool {
        let supTask = Task { @MainActor in
            ObjectCaptureSession.isSupported
        }
        return await supTask.value
    }
}


@Observable @MainActor
final class AppDataModel: Identifiable {
    static let instance = AppDataModel()

    /// The session that manages the object capture phase.
    ///
    /// Set the correct folder locations for the capture session using ``scanFolderManager``.
    var objectCaptureSession: ObjectCaptureSession? {
        willSet {
            detachListeners()
        }
        didSet {
            guard objectCaptureSession != nil else { return }
            attachListeners()
        }
    }

    /// The object that manages the reconstruction process of a set of images of an object into a 3D model.
    ///
    /// When the ``ReconstructionPrimaryView`` is active, hold the session here.
    private(set) var photogrammetrySession: PhotogrammetrySession?

    /// The folder set when a new capture session starts.
    private(set) var scanFolderManager: CaptureFolderManager?

    var messageList = TimedMessageList()

    var state: ModelState = .notSet {
        didSet {
            Logger.scanner3D.debug("didSet AppDataModel.state to \(self.state)")

            if state != oldValue {
                performStateTransition(from: oldValue, to: state)
            }
        }
    }

    var orbitState: OrbitState = .initial
    var orbit: Orbit = .orbit1
    var isObjectFlipped: Bool = false

    var hasIndicatedObjectCannotBeFlipped: Bool = false
    var hasIndicatedFlipObjectAnyway: Bool = false
    var isObjectFlippable: Bool {
        // Overrides the `objectNotFlippable` feedback if the user indicates
        // the object can flip or if they want to flip the object anyway.
        guard !hasIndicatedObjectCannotBeFlipped else { return false }
        guard !hasIndicatedFlipObjectAnyway else { return true }
        guard let session = objectCaptureSession else { return true }
        return !session.feedback.contains(.objectNotFlippable)
    }

    /// The error that indicates the object capture session failed.
    ///
    /// This error moves  ``state`` to ``ModelState/failed``.
    private(set) var error: Swift.Error?

    /// A Boolean value that determines whether the view shows a preview model.
    ///
    /// Default value is `false`.
    ///
    /// Uses ``setPreviewModelState(shown:)`` to properly maintain the pause state of
    /// the ``objectCaptureSession`` while showing the ``CapturePrimaryView``.
    /// Alternatively, hiding the ``CapturePrimaryView`` pauses the
    /// ``objectCaptureSession``.
    private(set) var showPreviewModel = false

    private init(objectCaptureSession: ObjectCaptureSession) {
        self.objectCaptureSession = objectCaptureSession
        state = .ready
    }

    // Leaves the model state in ready.
     private init() {
        state = .ready
        CaptureFolderManager.cleanupStaleScans()
    }

    // No deinit cleanup needed: `AppDataModel` is a singleton (`static let instance`), so
    // `deinit` never realistically fires. Real teardown already happens reliably via
    // `objectCaptureSession`'s `willSet` (calls `detachListeners()`) whenever the session is
    // reset — reached from `reset()`, itself reached from `endCapture()` and the
    // `.restart`/`.completed`/`.prepareToReconstruct` state transitions.

    /// Informs your app to rerun to the new capture view after recontruction and viewing.
    ///
    /// After reconstruction and viewing are complete, call `endCapture()` to
    /// inform the app it can go back to the new capture view.
    /// You can also call ``endCapture()`` after a canceled or failed
    /// reconstruction to go back to the start screen.
    func endCapture() {
        state = .completed
    }

    /// Ends the capture after its model was reviewed and handed to the item, and closes the
    /// capture UI. `endCapture()` alone went on to `.ready`, which starts a new capture session
    /// half a second later: after a finished scan a session ran unseen with the camera on.
    /// With `attached == false` the model stays in the scan folder: it was deleted there even
    /// when attaching had failed, and it was the only copy. See CODE_AUDIT_21 §5.21.
    func finishCapture(attached: Bool) {
        skipNextAutoRestart = true
        keepsModelOnReset = !attached
        finishedCaptures += 1
        state = .completed
    }

    /// Counts finished captures; the capture UI dismisses itself when it changes.
    private(set) var finishedCaptures = 0

    /// Set for the reset after a capture whose model could not be attached.
    private var keepsModelOnReset = false

    /// Set right before a cancel that's also dismissing the capture UI entirely, so
    /// `performStateTransition`'s usual "land on `.ready` → immediately start a new
    /// capture" behavior is skipped once. See ``cancelAndDismiss()``.
    private var skipNextAutoRestart = false

    /// Cancels the current capture and tells the state machine not to silently spin up
    /// a replacement session behind it.
    ///
    /// Call this — instead of `objectCaptureSession?.cancel()` directly — from any
    /// control that also dismisses the capture UI (see `CaptureCancelButton`). Apple's
    /// original sample always keeps its single capture screen on screen, so landing back
    /// on `.ready` after a cancel is meant to immediately offer a fresh capture; here the
    /// screen closes too, so without this a brand-new `ObjectCaptureSession` was started
    /// and left running invisibly, holding the camera and fighting the next session
    /// opened for the hardware (the Fig camera-source asserts, "No depth/confidence map
    /// available", stuck `shouldShowARKitCoachingView`, and growing ARFrame-retention
    /// warnings all trace back to that orphaned session).
    ///
    /// The model is reset right here instead of waiting for the session to report
    /// `.failed(.cancelled)`: Cancel is also available before detection has started, where
    /// that report is not something to rely on, and a session left behind would keep the
    /// camera and be shown again on the next open.
    func cancelAndDismiss() {
        skipNextAutoRestart = true
        objectCaptureSession?.cancel()
        state = .restart
    }

    /// Starts a new capture session if one isn't already running.
    ///
    /// Call when presenting the capture UI: `cancelAndDismiss()` leaves the model
    /// idling at `.ready` with no session so the camera is released immediately, so
    /// reopening the capture screen needs an explicit kick to start a fresh one.
    func beginCaptureIfNeeded() {
        guard state == .ready, objectCaptureSession == nil else { return }
        scheduleStartNewCapture()
    }

    /// Task started by the most recent `scheduleStartNewCapture()`, tracked so a rapid
    /// second call (e.g. `beginCaptureIfNeeded()` firing right after the `.ready` case
    /// in `performStateTransition` already scheduled one) cancels the first instead of
    /// both racing to claim the camera.
    private var pendingCaptureStartTask: Task<Void, Never>?

    /// Starts a new capture session after a short delay instead of immediately.
    ///
    /// Dropping the last reference to the previous `ObjectCaptureSession` runs its
    /// `deinit` synchronously, but the actual handoff of the physical camera back to the
    /// system underneath that isn't guaranteed to finish in the same instant — starting
    /// a replacement `ObjectCaptureSession` right away can reach AVFoundation while the
    /// old one is still mid-teardown, which surfaces as `FigCaptureSourceRemote` camera
    /// errors (`err=-12784`) and a session that never gets a working camera feed. A
    /// small explicit gap here gives that teardown room to actually finish first.
    private func scheduleStartNewCapture() {
        pendingCaptureStartTask?.cancel()
        pendingCaptureStartTask = Task { [weak self] in
            try? await Task.sleep(for: Self.cameraTeardownDelay)
            guard !Task.isCancelled, let self, self.state == .ready, self.objectCaptureSession == nil else { return }
            guard self.startNewCapture() else {
                Logger.scanner3D.error("Starting new capture failed!")
                return
            }
        }
    }

    /// How long `scheduleStartNewCapture()` waits before starting a replacement
    /// `ObjectCaptureSession`, to give the previous session's camera teardown time to
    /// actually finish (see that method's own doc comment). Too short reintroduces the
    /// `FigCaptureSourceRemote err=-12784` race that comment describes.
    private static let cameraTeardownDelay: Duration = .milliseconds(500)

    // This sample doesn't modify the `showPreviewModel` directly. The `CapturePrimaryView`
    // remains on screen and blurred underneath, it doesn't pause.  So, pause
    // the `objectCaptureSession` after showing the model and start it before
    // dismissing the model.
    func setPreviewModelState(shown: Bool) {
        guard shown != showPreviewModel else { return }
        if shown {
            showPreviewModel = true
            objectCaptureSession?.pause()
        } else {
            objectCaptureSession?.resume()
            showPreviewModel = false
        }
    }

    // - MARK: Private Interface

    private var currentFeedback: Set<Feedback> = []

    private typealias Feedback = ObjectCaptureSession.Feedback
    private typealias Tracking = ObjectCaptureSession.Tracking
    
    private var tasks: [ Task<Void, Never> ] = []

    /// Tracks the background snapshots-folder cleanup task so a stale one from a previous
    /// session doesn't keep running untracked. `AppDataModel` is a singleton (`static let
    /// instance`), so `deinit` never realistically fires — `reset()` is the actual reachable
    /// teardown point between capture sessions.
    private var cleanupTask: Task<Void, Never>?

    @MainActor
    private func attachListeners() {
        Logger.scanner3D.debug("Attaching listeners...")
        guard let model = objectCaptureSession else {
            Logger.scanner3D.error("attachListeners() called with no objectCaptureSession; skipping.")
            return
        }

        tasks.append(Task<Void, Never> { [weak self] in
                for await newFeedback in model.feedbackUpdates {
                    Logger.scanner3D.debug("Task got async feedback change to: \(String(describing: newFeedback))")
                    self?.updateFeedbackMessages(for: newFeedback)
                }
            Logger.scanner3D.log("^^^ Got nil from stateUpdates iterator!  Ending observation task...")
        })
        tasks.append(Task<Void, Never> { [weak self] in
            for await newState in model.stateUpdates {
                Logger.scanner3D.debug("Task got async state change to: \(String(describing: newState))")
                // A session that was already replaced or reset must not drive the model:
                // its late `.failed(.cancelled)` would restart a capture nobody sees.
                guard let self, self.objectCaptureSession === model else { break }
                self.onStateChanged(newState: newState)
                }
            Logger.scanner3D.log("^^^ Got nil from stateUpdates iterator!  Ending observation task...")
        })
    }

    private func detachListeners() {
        Logger.scanner3D.debug("Detaching listeners...")
        for task in tasks {
            task.cancel()
        }
        tasks.removeAll()
    }

    /// Creates a new object capture session.
    private func startNewCapture() -> Bool {
        Logger.scanner3D.log("startNewCapture() called...")
        // Graceful failures rather than `preconditionFailure` — the only call
        // site today is gated by an `isSupported()` check in the UI, but this
        // function performs no re-check itself, so a future entry point (a
        // Shortcuts/App Intent action, or a capability-check race) should
        // surface an error state instead of crashing the whole app. See
        // CODE_AUDIT §5.4.
        guard ObjectCaptureSession.isSupported else {
            Logger.scanner3D.error("ObjectCaptureSession is not supported on this device!")
            return false
        }

        guard let folderManager = CaptureFolderManager() else {
            return false
        }

        scanFolderManager = folderManager
        objectCaptureSession = ObjectCaptureSession()

        guard let session = objectCaptureSession else {
            Logger.scanner3D.error("startNewCapture() got unexpectedly nil session!")
            return false
        }

        var configuration = ObjectCaptureSession.Configuration()
        configuration.checkpointDirectory = folderManager.snapshotsFolder
        configuration.isOverCaptureEnabled = true
        Logger.scanner3D.log("Enabling overcapture...")

        // Starts the initial segment and sets the output locations.
        session.start(imagesDirectory: folderManager.imagesFolder,
                      configuration: configuration)

        if case let .failed(error) = session.state {
            Logger.scanner3D.error("Got error starting session! \(String(describing: error))")
            switchToErrorState(error: error)
        } else {
            state = .capturing
        }

        return true
    }

    private func switchToErrorState(error: Swift.Error) {
        // Sets the error first since the transitions assume it's non-`nil`.
        self.error = error
        state = .failed
    }

    // This sample calls `startReconstruction()` from the `ReconstructionPrimaryView` asynchronous
    // task after it's on the screen.
    /// Moves model state from prepare to reconstruct to reconstructing
    ///
    /// See ``ModelState/prepareToReconstruct``
    /// and ``ModelState/reconstructing``.
    private func startReconstruction() throws {
        Logger.scanner3D.debug("startReconstruction() called.")

        guard let scanFolderManager else {
            throw CocoaError(.fileNoSuchFile)
        }

        var configuration = PhotogrammetrySession.Configuration()
        configuration.checkpointDirectory = scanFolderManager.snapshotsFolder
        photogrammetrySession = try PhotogrammetrySession(
            input: scanFolderManager.imagesFolder,
            configuration: configuration)

        state = .reconstructing
    }

    private func reset() {
        Logger.scanner3D.info("reset() called...")
        cleanupTask?.cancel()
        cleanupTask = nil

        // Removes the entire capture folder tree (Images/Snapshots/Models). By the time this
        // runs, any produced model has already been attached to its item — `onCaptureFinished`
        // (in `ReconstructionPrimaryView`) copies it into managed storage before `endCapture()`
        // moves state to `.completed`. For a cancelled/failed scan this simply discards the
        // leftover capture photos instead of letting them accumulate in Documents indefinitely.
        //
        // A model that could not be attached is the only copy: its folder stays, and only the
        // capture photos and snapshots go. See CODE_AUDIT_21 §5.21.
        let keepsModel = keepsModelOnReset
        keepsModelOnReset = false
        if let scanFolderManager {
            let removed = keepsModel
                ? [scanFolderManager.imagesFolder, scanFolderManager.snapshotsFolder]
                : [scanFolderManager.rootScanFolder]
            if keepsModel {
                Logger.scanner3D.error("The scanned model was not attached; it is kept in \(scanFolderManager.modelsFolder.path(percentEncoded: false), privacy: .private)")
            }
            cleanupTask = Task(priority: .background) { @concurrent in
                guard !Task.isCancelled else { return }
                for url in removed {
                    try? FileManager.default.removeItem(at: url)
                }
            }
        }

        photogrammetrySession?.cancel()
        photogrammetrySession = nil
        objectCaptureSession = nil
        scanFolderManager = nil
        showPreviewModel = false
        orbit = .orbit1
        orbitState = .initial
        isObjectFlipped = false
        state = .ready
    }

    private func onStateChanged(newState: ObjectCaptureSession.CaptureState) {
        Logger.scanner3D.info("ObjectCaptureSession switched to state: \(String(describing: newState))")
        if case .completed = newState {
            Logger.scanner3D.log("ObjectCaptureSession moved to .completed state.  Switch app model to reconstruction...")
            state = .prepareToReconstruct
        } else if case let .failed(error) = newState {
            Logger.scanner3D.error("ObjectCaptureSession moved to error state \(String(describing: error))...")
            if case ObjectCaptureSession.Error.cancelled = error {
                state = .restart
            } else {
                switchToErrorState(error: error)
            }
        }
    }

    private func updateFeedbackMessages(for feedback: Set<Feedback>) {
        // Compares the incoming feedback with the previous feedback to find
        // the intersection.
        let persistentFeedback = currentFeedback.intersection(feedback)

        // Finds the feedback that's no longer active.
        let feedbackToRemove = currentFeedback.subtracting(persistentFeedback)
        for thisFeedback in feedbackToRemove {
            if let feedbackString = FeedbackMessages.getFeedbackString(for: thisFeedback) {
                messageList.remove(feedbackString)
            }
        }

        // Finds new feedback.
        let feedbackToAdd = feedback.subtracting(persistentFeedback)
        for thisFeedback in feedbackToAdd {
            if let feedbackString = FeedbackMessages.getFeedbackString(for: thisFeedback) {
                messageList.add(feedbackString)
            }
        }

        currentFeedback = feedback
    }

    private func performStateTransition(from fromState: ModelState, to toState: ModelState) {
        if fromState == .failed {
            error = nil
        }

        switch toState {
            case .ready:
                guard !skipNextAutoRestart else {
                    skipNextAutoRestart = false
                    break
                }
                scheduleStartNewCapture()
            case .capturing:
                orbitState = .initial
            case .prepareToReconstruct:
                // Cleans up the session to free GPU and memory resources.
                objectCaptureSession = nil
                if let scanFolderManager {
                    Task { try? await scanFolderManager.loadShots() }
                }
                do {
                    try startReconstruction()
                } catch {
                    Logger.scanner3D.error("Reconstructing failed: \(String(describing: error))")
                    switchToErrorState(error: error)
                }
            case .restart, .completed:
                reset()
            case .viewing:
                photogrammetrySession = nil

                // Removes snapshots folder to free up space after generating the model.
                // Genuinely benefits from running off the main actor (plain file I/O, no MainActor
                // work needed) — tracked so `reset()` can cancel a stale one.
                if let snapshotsFolder = scanFolderManager?.snapshotsFolder {
                    cleanupTask?.cancel()
                    cleanupTask = Task(priority: .background) { @concurrent in
                        guard !Task.isCancelled else { return }
                        try? FileManager.default.removeItem(at: snapshotsFolder)
                    }
                }

            case .failed:
            Logger.scanner3D.error("App failed state error=\(String(describing: self.error))")
                // Shows error screen.
            default:
                break
        }
    }

    func determineCurrentOnboardingState() -> OnboardingState? {
        guard let session = objectCaptureSession else { return nil }
        let orbitCompleted = session.userCompletedScanPass
        var currentState = OnboardingState.tooFewImages
        if session.numberOfShotsTaken >= CaptureConstants.minNumImages {
            switch orbit {
                case .orbit1:
                    currentState = orbitCompleted ? .firstSegmentComplete : .firstSegmentNeedsWork
                case .orbit2:
                    currentState = orbitCompleted ? .secondSegmentComplete : .secondSegmentNeedsWork
                case .orbit3:
                    currentState = orbitCompleted ? .thirdSegmentComplete : .thirdSegmentNeedsWork
            }
        }
        return currentState
    }

}

    /// Capture-flow tuning constants unrelated to localization (see CODE_AUDIT_Space §4.5 —
    /// this used to live inside the `LocString` localization enum).
    enum CaptureConstants {
        static let minNumImages = 10
    }

#endif
