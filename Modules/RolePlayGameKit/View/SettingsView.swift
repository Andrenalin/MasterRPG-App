// @copyright André Trettin

import CoreRPG
import SwiftUI
import AdventureRPG
import AudioRPG
import GameRPG
import PdfRPG
import PhotoRPG
import SpaceRPG
import TableRPG
import MapRPG
import CharacterRPG
import WeatherRPG
import DiceRPG



@MainActor
public protocol StoreManipulable: Sendable {
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

    @State private var showResetJoinCodesAlert = false
    @State private var didResetJoinCodes = false
    
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

            // tvOS never honors this toggle — AppModel hardcodes
            // `useCloudKit: false` there (Core Data boots local-only
            // regardless of this setting), so the toggle is hidden rather
            // than shown in a state the app doesn't actually implement. See
            // CODE_AUDIT_10 §5.1.
            #if !os(tvOS)
            StorageOptionEditor {
                if let model = store.coreDataInitModel {
                    CloudKitSyncStatusView(syncState: model.cloudKitSyncState, lastSync: model.lastSuccessfulSync)
                }
            }
            #endif

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
                    withAnimation { showResetJoinCodesAlert.toggle() }
                } label: {
                    Label {
                        Text("Reset Join Codes", bundle: .module)
                    } icon: {
                        Image(systemName: "key.slash")
                    }
                }
                .alert(Text("Reset Join Codes?", bundle: .module), isPresented: $showResetJoinCodesAlert) {
                    Button(role: .cancel) {
                    } label: {
                        Text("Cancel", bundle: .module)
                    }
                    Button(role: .destructive) {
                        store.gameRoot.resetJoinCodes()
                        withAnimation { didResetJoinCodes = true }
                    } label: {
                        Text("Reset", bundle: .module)
                    }
                } message: {
                    Text(
                        "Generates new codes for hosting and joining this device's game over the local network, and forgets the last code used to join another Game Master. Anyone using the old codes will need the new ones to connect.",
                        bundle: .module
                    )
                }
            } header: {
                Text("Game Join Codes", bundle: .module)
            } footer: {
                if didResetJoinCodes {
                    Label {
                        Text("Join codes have been reset.", bundle: .module)
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                    }
                    .foregroundStyle(.green)
                } else {
                    Text("These codes are stored in the Keychain on this device only and are never synced with iCloud.", bundle: .module)
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
                    Text("Be careful, this removes all data from the database, all files in local and appCloud storage associated with the database. Files in other or iCloud will not be touched.", bundle: .module)
                }
            } header: {
                Text("Reset", bundle: .module)
            } footer: {
                Text("Be careful, this removes all data and resets the database.", bundle: .module)
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
