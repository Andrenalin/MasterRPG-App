// @copyright André Trettin

import CoreRPG
import SwiftUI
import AdventureRPG
import AudioRPG
import PdfRPG
import PhotoRPG
import SpaceRPG
import TableRPG
import MapRPG
import CharacterRPG
import WeatherRPG
import DiceRPG



@MainActor
public protocol StoreManiplable: Sendable {
    func resetData() async
    func validate()
}

public struct SettingsView: View {
    public init(store: AppModel) {
        self.store = store
    }
    
    let store: AppModel

    @Environment(\.navigator) private var navigator
    @State private var didReplayTips = false
    
    @State private var showResetAlert = false
    @State private var isThemePickerPresented = false
    
    public var body: some View {
        List {
            ThemeSettingsView(isPickerPresented: $isThemePickerPresented)
                       
            SectionGroupEditorView {
                Button {
                    navigator.navigate(to: SettingsRoute.supporter, method: .managedSheet)
                } label: {
                    Label {
                        Text("Support MasterRPG", bundle: .module)
                    } icon: {
                        Image(systemName: "crown.fill")
                    }
                }
            } header: {
                Text("Supporter", bundle: .module)
            } footer: {
                Text(
                    "Optional one-time support purchases add only a colored crown to your game name. No features are locked.",
                    bundle: .module
                )
            }

            StorageOptionEditor {
                if let model = store.coreDataInitModel {
                    CloudKitSyncStatusView(syncState: model.cloudKitSyncState, lastSync: model.lastSuccessfulSync)
                }
            }

            SectionGroupEditorView {
                Button {
                    navigator.navigate(to: SettingsRoute.exportData, method: .managedSheet)
                } label: {
                    Label { Text("Export", bundle: .module) } icon: { Image(systemName: "square.and.arrow.up") }
                }

                Button {
                    navigator.navigate(to: SettingsRoute.importData, method: .managedCover)
                } label: {
                    Label { Text("Import", bundle: .module) } icon: { Image(systemName: "square.and.arrow.down") }
                }

            } header: {
                Text("Manage Data", bundle: .module)
            }
            

            SectionGroupEditorView {
                Button {
                    navigator.navigate(to: SettingsRoute.validate, method: .managedSheet)
                } label: {
                    Label { Text("Validate Folders", bundle: .module) } icon: { Image(systemName: "folder") }
                }
            } header: {
                Text("Data Checks", bundle: .module)
            }
            
            SectionGroupEditorView {
                Button {
                    Task {
                        didReplayTips = await MasterRPGTips.replay()
                    }
                } label: {
                    Label {
                        Text("Show Tips Again", bundle: .module)
                    } icon: {
                        Image(systemName: "lightbulb")
                    }
                }
            } header: {
                Text("Tips", bundle: .module)
            } footer: {
                if didReplayTips {
                    Label {
                        Text("Tips are ready to show again.", bundle: .module)
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                    }
                    .foregroundStyle(.green)
                } else {
                    Text("Restores in-app guidance for creating, organizing, linking, and playing.", bundle: .module)
                }
            }
            
            SectionGroupEditorView {
                Button(role: .destructive) {
                    withAnimation { showResetAlert.toggle() }
                } label: {
                    Label {
                        Text("Reset Data", bundle: .module)
                    } icon: {
                        Image(systemName: "xmark.circle")
                    }
                }
                .alert(Text("Really Reset?", bundle: .module), isPresented: $showResetAlert) {
                    Button(role: .cancel) {
                    } label: {
                        Text("Cancel", bundle: .module)
                    }
                    Button(role: .destructive) {
                        let localStore = store
                        Task {
                            await localStore.resetData()
                        }
                    } label: {
                        Text("Reset", bundle: .module)
                    }
                } message: {
                    Text("Becareful this removes all data from the database, all files in local and appCloud storage associated with the database. Files in other or iCloud will not be touched.", bundle: .module)
                }
            } header: {
                Text("Reset", bundle: .module)
            } footer: {
                Text("Becareful this removes all data and resets the database.", bundle: .module)
            }
        }
        .themedListSurface()
        .navigationTitle(Text("Settings", bundle: .module))
        .sheet(isPresented: $isThemePickerPresented) {
            ThemePickerView()
        }
        .environment(store.settingsModel)
    }
}

#Preview {
    SettingsView(store: .preview)
        .preferredColorScheme(.dark)
}
