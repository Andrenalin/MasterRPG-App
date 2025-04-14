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

    var body: some View {
        let _ = Self._printChanges()
        let _ = print(RouteActions.tabId)

        TabNavigation(appStore: appStore, tabId: RouteActions.tabId)
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
