// @copyright André Trettin

#if !os(tvOS)
import CoreRPG
import CoreTransferable
import GroupActivities
import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

#Preview {
    SharePlayButton("Start SharePlay", activity: RPGActivity(adventureTitle: "Preview Adventure"))
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
        SharePlayButton("Play RPG Online", activity: RPGActivity())
        .opacity(sharePlayStore.canActivateSharePlay ? 0 : 1)
        .allowsHitTesting(!sharePlayStore.canActivateSharePlay)
        .accessibilityHidden(sharePlayStore.canActivateSharePlay)
        .disabled(sharePlayStore.canActivateSharePlay)
    }
}

/// Opens the system sheet that invites people to a SharePlay session. Only shown while this
/// device can't start a group session directly (see `GameSharePlayButton`), so it has no
/// direct-activation path: that branch was unreachable. See CODE_AUDIT_19 §8.4.
struct SharePlayButton<ActivityType: GroupActivity & Transferable & Sendable>: View {
    @State
    private var isActivitySharingViewPresented = false

    let text: LocalizedStringKey
    let activity: ActivityType

    init(_ text: LocalizedStringKey, activity: ActivityType) {
        self.text = text
        self.activity = activity
    }

    var body: some View {
        ZStack {
#if !os(tvOS)
            ShareLink(item: activity, preview: SharePreview(Text(text, bundle: .module)))
                .hidden()
                .accessibilityHidden(true)
#endif
            Button {
                isActivitySharingViewPresented = true
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
