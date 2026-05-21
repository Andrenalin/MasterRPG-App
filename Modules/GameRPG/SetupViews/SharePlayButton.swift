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

struct SharePlayButton<ActivityType: GroupActivity & Transferable & Sendable>: View {
    @ObservedObject
    private var groupStateObserver = GroupStateObserver()
    
    @State
    private var isActivitySharingViewPresented = false
    
    @State
    private var isActivationErrorViewPresented = false
    
    private let activitySharingView: ActivitySharingView<ActivityType>
    
    let text: any StringProtocol
    let activity: ActivityType
    
    init(_ text: any StringProtocol, activity: ActivityType) {
        self.text = text
        self.activity = activity
        self.activitySharingView = ActivitySharingView {
            activity
        }
    }
    
    var body: some View {
        ZStack {
#if !os(tvOS)
            ShareLink(item: activity, preview: SharePreview(text)).hidden()
#endif
            Button(text, systemImage: "shareplay") {
                if groupStateObserver.isEligibleForGroupSession {
                    Task.detached {
                        do {
                            _ = try await activity.activate()
                        } catch {
                            print("Error activating activity: \(error)")
                            
                            Task { @MainActor in
                                isActivationErrorViewPresented = true
                            }
                        }
                    }
                } else {
                    isActivitySharingViewPresented = true
                }
            }
            .tint(.green)
            .sheet(isPresented: $isActivitySharingViewPresented) {
                ManagedPresentationView {
                    activitySharingView
                }
            }
            .alert("Unable to start game", isPresented: $isActivationErrorViewPresented) {
                Button("Ok", role: .cancel) { }
            } message: {
                Text("Please try again later.")
            }
        }
    }
}

#if os(macOS)
struct ActivitySharingView<ActivityType: GroupActivity & Sendable>: NSViewControllerRepresentable {
    let preparationHandler: () async throws -> ActivityType
  
    func makeNSViewController(context: Context) -> GroupActivitySharingController {
        GroupActivitySharingController(preparationHandler: preparationHandler)
    }
    
    func updateNSViewController(_ nsViewController: GroupActivitySharingController, context: Context) {}
}
#else
struct ActivitySharingView<ActivityType: GroupActivity & Sendable>: UIViewControllerRepresentable {
    let preparationHandler: () async throws -> ActivityType

    func makeUIViewController(context: Context) -> GroupActivitySharingController {
        GroupActivitySharingController(preparationHandler: preparationHandler)
    }

    func updateUIViewController(_: GroupActivitySharingController, context: Context) {}
}
#endif


#endif
