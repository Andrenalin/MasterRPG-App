// @copyright André Trettin

import SwiftUI

/// Lets the confirmation alert's own dismissal animation finish before the app quits —
/// quitting mid-animation would just cut it off. See CODE_AUDIT §9.14.
/// (A plain file-private constant rather than a `static let` member: Swift doesn't support
/// stored `static` properties on a generic type like `StorageOptionEditor<Sync>`.)
private let quitAfterAlertDismissDelay: Duration = .seconds(0.1)

public struct StorageOptionEditor<Sync: View>: View {
    /// - Parameter beforeQuit: Awaited before the process exits, so any edits still
    ///   queued in memory (see CODE_AUDIT_17 §5.2) reach disk before the store
    ///   switch terminates the app. Defaults to a no-op for callers with nothing to
    ///   flush (e.g. previews). See CODE_AUDIT_17 §5.3.
    public init(beforeQuit: @escaping @Sendable () async -> Void = {}, @ViewBuilder sync: () -> Sync) {
        self.beforeQuit = beforeQuit
        syncView = sync()
    }

    let beforeQuit: @Sendable () async -> Void
    let syncView: Sync
    
    @Environment(AppSettingsModel.self) private var appSettings
    @Environment(\.cloudKitAccountChecksEnabled) private var cloudKitAccountChecksEnabled
    @Environment(\.appTheme) private var theme
    
    @State private var showExitAlert = false
    @State private var useCloudKit = false
    
    @State private var iCloudAvailable: CloudKitAccountStatus = .notChecked
    
    public var body: some View {
        @Bindable var appSettings = appSettings
        SectionGroupEditorView {
            Text("iCloud Account Status: \(iCloudAvailable.title)", bundle: .module)
            
            Toggle(isOn: $useCloudKit) {
                Text("Store Database in iCloud", bundle: .module)
            }
            .tint(theme.accentColor)
            .disabled(disabledUseCloud)
            .onChange(of: appSettings.useCloudKit, initial: true) {
                useCloudKit <=> appSettings.useCloudKit
            }
            .onChange(of: useCloudKit, initial: false) {
                guard useCloudKit != appSettings.useCloudKit else { return }
                withAnimation { showExitAlert.toggle() }
            }
            .alert(Text("Change Database?", bundle: .module), isPresented: $showExitAlert) {
                Button {
                    appSettings.resetCloudKit(to: useCloudKit)
                    Task {
                        try? await Task.sleep(for: quitAfterAlertDismissDelay)
                        await beforeQuit()
                        Darwin.exit(0)
                    }
                } label: {
                    Text("Change Database and quit the app", bundle: .module)
                }
                Button {
                    withAnimation { useCloudKit = appSettings.useCloudKit }
                } label: {
                    Text("Cancel", bundle: .module)
                }
            } message: {
                Text("The app will be terminated to apply the database change.", bundle: .module)
            }
            
            if useCloudKit {
                syncView
            }
            
        } header: {
            Text("Database Settings", bundle: .module)
        } footer: {
            Text("Settings about the Database storage. You can switch back and furth, the database will not be removed. If you like you can export the current database and import it the other one. Use iCloud if you want automatical sync between the devices.", bundle: .module)
        }
        .task {
            guard cloudKitAccountChecksEnabled else { return }
            iCloudAvailable = await CloudKitAccountController.checkAccountStatus()
        }
    }
    
    var disabledUseCloud: Bool {
        guard !useCloudKit else { return false }
        return iCloudAvailable != .available
    }
}

#Preview {
    StorageOptionEditor {
        Text("Sync View")
    }
        .environment(AppSettingsModel.previewFixture())
        .cloudKitAccountChecksEnabled(false)
        .preferredColorScheme(.dark)
}

private extension EnvironmentValues {
    @Entry var cloudKitAccountChecksEnabled: Bool = true
}

public extension View {
    func cloudKitAccountChecksEnabled(_ enabled: Bool) -> some View {
        environment(\.cloudKitAccountChecksEnabled, enabled)
    }
}
