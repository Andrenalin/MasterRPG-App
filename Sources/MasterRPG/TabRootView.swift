// @copyright André Trettin

import RPGAdventures
import AndrenalinKit
import DiceRPG
import RoleGameKit
import AudioRPG
import RPGGame
import MapRPG
import PdfRPG
import PhotoRPG
import SpaceRPG
import TableRPG
import CharacterRPG
import SwiftUI
import WeatherRPG

struct TabRootView: View {
    let appModel: AppModel
    let editorOnly: Bool

    @Environment(\.appSizeMode) private var appSizeMode

    var body: some View {
        let _ = Self._printChanges()

        layout
            .onChange(of: appSizeMode) { oldValue, newValue in
                appModel.resetNavigation()
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
        appModel.selectionSheetLinkModel
    }
    
    private var fullScreenBinding: Binding<Bool> {
        Binding {
            appModel.selectionSheetLinkModel.selectionFullScreen
        } set: {
            appModel.selectionSheetLinkModel.selectionFullScreen = $0
        }
    }

    private var sheetBinding: Binding<Bool> {
        Binding {
            appModel.selectionSheetLinkModel.selection
        } set: {
            appModel.selectionSheetLinkModel.selection = $0
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
    TabRootView(appModel: .preview, editorOnly: false)
}
