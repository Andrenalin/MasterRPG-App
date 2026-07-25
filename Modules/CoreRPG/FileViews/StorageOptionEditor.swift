// @copyright André Trettin

import SwiftUI

public struct StorageOptionEditor<Sync: View>: View {
    public init(@ViewBuilder sync: () -> Sync) {
        syncView = sync()
    }
    
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
                        try? await Task.sleep(for: .seconds(0.1))
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
            Text("Databse Settings", bundle: .module)
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

private struct CloudKitAccountChecksEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

private extension EnvironmentValues {
    var cloudKitAccountChecksEnabled: Bool {
        get { self[CloudKitAccountChecksEnabledKey.self] }
        set { self[CloudKitAccountChecksEnabledKey.self] = newValue }
    }
}

public extension View {
    func cloudKitAccountChecksEnabled(_ enabled: Bool) -> some View {
        environment(\.cloudKitAccountChecksEnabled, enabled)
    }
}
