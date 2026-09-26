// @copyright André Trettin

#if !os(tvOS)
import CoreRPG
import CoreTransferable
import GroupActivities
import SwiftUI
import os.log

#if os(macOS)
import AppKit
#else
import UIKit
#endif

#Preview {
    SharePlayButton("Start SharePlay", activity: RPGActivity(adventureTitle: "Preview Adventure"), isEligibleForGroupSession: false)
}

/// The setup screens' SharePlay entry, shown only while this device can't start a group
/// session directly. Shared by the adventure and player setup views (they had identical
/// copies). See CODE_AUDIT_18 §9.14.
struct GameSharePlayButton: View {
    let root: GameRoot

    private var sharePlayStore: RPGSharePlayController {
        root.networkStore.sharePlayStore
    }

    var body: some View {
        SharePlayButton(
            "Play RPG Online",
            activity: RPGActivity(),
            isEligibleForGroupSession: sharePlayStore.canActivateSharePlay
        )
        .opacity(sharePlayStore.canActivateSharePlay ? 0 : 1)
        .allowsHitTesting(!sharePlayStore.canActivateSharePlay)
        .accessibilityHidden(sharePlayStore.canActivateSharePlay)
    }
}

struct SharePlayButton<ActivityType: GroupActivity & Transferable & Sendable>: View {
    /// Injected from `RPGSharePlayController.canActivateSharePlay`, which already observes
    /// `GroupStateObserver` for the app's lifetime. The view used to own an observer through
    /// `@ObservedObject`, which recreated it (and briefly read `false`) on every parent
    /// re-render. See CODE_AUDIT_18 §8.2.
    let isEligibleForGroupSession: Bool

    @State
    private var isActivitySharingViewPresented = false
    
    @State
    private var isActivationErrorViewPresented = false
    
    let text: LocalizedStringKey
    let activity: ActivityType

    init(_ text: LocalizedStringKey, activity: ActivityType, isEligibleForGroupSession: Bool) {
        self.text = text
        self.activity = activity
        self.isEligibleForGroupSession = isEligibleForGroupSession
    }

    var body: some View {
        ZStack {
#if !os(tvOS)
            ShareLink(item: activity, preview: SharePreview(Text(text, bundle: .module)))
                .hidden()
                .accessibilityHidden(true)
#endif
            Button {
                if isEligibleForGroupSession {
                    // No need to detach: this action closure is already MainActor-isolated
                    // (created inside `body`, which is @MainActor), so a plain structured
                    // Task inherits that isolation — no nested Task needed to set the flag.
                    Task { @MainActor in
                        do {
                            _ = try await activity.activate()
                        } catch {
                            Logger.sharePlay.error("Error activating activity: \(error.localizedDescription, privacy: .public)")
                            isActivationErrorViewPresented = true
                        }
                    }
                } else {
                    isActivitySharingViewPresented = true
                }
            } label: {
                Label {
                    Text(text, bundle: .module)
                } icon: {
                    Image(systemName: "shareplay")
                }
            }
            .tint(.green)
            .sheet(isPresented: $isActivitySharingViewPresented) {
                ManagedPresentationView {
                    ActivitySharingView(preparationHandler: { activity }) {
                        isActivitySharingViewPresented = false
                    }
                }
            }
            .alert(Text("Unable to start game", bundle: .module), isPresented: $isActivationErrorViewPresented) {
                Button(role: .cancel) { } label: { Text("OK", bundle: .module) }
            } message: {
                Text("Please try again later.", bundle: .module)
            }
        }
    }
}

#if os(macOS)
struct ActivitySharingView<ActivityType: GroupActivity & Sendable>: NSViewControllerRepresentable {
    let preparationHandler: () async throws -> ActivityType
    let onCompletion: () -> Void

    func makeNSViewController(context: Context) -> GroupActivitySharingController {
        let controller = GroupActivitySharingController(preparationHandler: preparationHandler)
        Task {
            _ = await controller.result
            onCompletion()
        }
        return controller
    }

    func updateNSViewController(_ nsViewController: GroupActivitySharingController, context: Context) {}
}
#else
struct ActivitySharingView<ActivityType: GroupActivity & Sendable>: UIViewControllerRepresentable {
    let preparationHandler: () async throws -> ActivityType
    let onCompletion: () -> Void

    func makeUIViewController(context: Context) -> GroupActivitySharingController {
        let controller = GroupActivitySharingController(preparationHandler: preparationHandler)
        Task {
            _ = await controller.result
            onCompletion()
        }
        return controller
    }

    func updateUIViewController(_: GroupActivitySharingController, context: Context) {}
}
#endif


#endif
