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
    SharePlayButton("Start SharePlay", activity: RPGActivity(adventureTitle: "Preview Adventure"))
}

struct SharePlayButton<ActivityType: GroupActivity & Transferable & Sendable>: View {
    @ObservedObject
    private var groupStateObserver = GroupStateObserver()
    
    @State
    private var isActivitySharingViewPresented = false
    
    @State
    private var isActivationErrorViewPresented = false
    
    let text: any StringProtocol
    let activity: ActivityType

    init(_ text: any StringProtocol, activity: ActivityType) {
        self.text = text
        self.activity = activity
    }

    var body: some View {
        ZStack {
#if !os(tvOS)
            ShareLink(item: activity, preview: SharePreview(text))
                .hidden()
                .accessibilityHidden(true)
#endif
            Button(text, systemImage: "shareplay") {
                if groupStateObserver.isEligibleForGroupSession {
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
