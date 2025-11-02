// @copyright André Trettin

import RPGAdventures
import AndrenalinKit
import RPGDie
import RoleGameKit
import RPGAudios
import RPGGame
import RPGMaps
import RPGPdfs
import RPGPhotos
import RPGSpaces
import RPGTables
import RPGValues
import SwiftUI
import RPGWeathers

struct TabRootView: View {
    let appStore: AppStore
    let editorOnly: Bool

    @Environment(\.appSizeMode) private var appSizeMode

    var body: some View {
        let _ = Self._printChanges()

        layout
            .onChange(of: appSizeMode) { oldValue, newValue in
                appStore.resetNavigation()
            }
            .sizedSheet(isPresented: isSingleSizedSheetPresented(selectionSheetLinkModel: selectionSheetLinkModel)) {
                selectionSheetLinkModel.dismissedAction?()
            } content: {
                Group {
                    if let view = selectionSheetLinkModel.selectionView {
                        view
                            .itemListConfiguration(modalOk: true) {
                                selectionSheetLinkModel.dismissedAction?()
                                selectionSheetLinkModel.selection = false
                            }
                            .environment(selectionSheetLinkModel)
                    }
                }
            }
            .sheetFullScreen(isPresented: fullScreenBinding, idealSize: selectionSheetLinkModel.idealSize ?? CGSize(width: 800, height: 600), onDismiss: {
                selectionSheetLinkModel.dismissedFullAction?()
                selectionSheetLinkModel.selectionFullScreen = false
            }) {
                Group {
                    if let view = selectionSheetLinkModel.selectionFullView {
                        view
                            .itemListConfiguration {
                                selectionSheetLinkModel.dismissedFullAction?()
                                selectionSheetLinkModel.selectionFullScreen = false
                            }
                            .environment(selectionSheetLinkModel)
                            .sizedSheet(isPresented: sheetBinding) {
                                selectionSheetLinkModel.dismissedAction?()
                            } content: {
                                Group {
                                    if let view = selectionSheetLinkModel.selectionView {
                                        view
                                            .itemListConfiguration(modalOk: true) {
                                                selectionSheetLinkModel.dismissedAction?()
                                                selectionSheetLinkModel.selection = false
                                            }
                                            .environment(selectionSheetLinkModel)
                                    }
                                }
                            }
                    }
                }
            }
    }
    
    private var layout: AppRootType {
        valueFor(iOS: appSizeMode == .compact ? .tabbed : .split, macOS: .tabbedSplit, tvOS: .tabbed, visionOS: .split)
    }
    
    private var selectionSheetLinkModel: SelectionSheetLinkModel {
        appStore.selectionSheetLinkModel
    }
    
    private var fullScreenBinding: Binding<Bool> {
        Binding {
            appStore.selectionSheetLinkModel.selectionFullScreen
        } set: {
            appStore.selectionSheetLinkModel.selectionFullScreen = $0
        }
    }

    private var sheetBinding: Binding<Bool> {
        Binding {
            appStore.selectionSheetLinkModel.selection
        } set: {
            appStore.selectionSheetLinkModel.selection = $0
        }
    }

    private func isSingleSizedSheetPresented(selectionSheetLinkModel: SelectionSheetLinkModel) -> Binding<Bool> {
        Binding {
            !selectionSheetLinkModel.selectionFullScreen && selectionSheetLinkModel.selection
        } set: {
            if !$0 {
                selectionSheetLinkModel.selection = false
            }
        }
    }
}

#Preview {
    TabRootView(appStore: .preview, editorOnly: false)
}
