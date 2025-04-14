// @copyright André Trettin

import AndrenalinKit
import RPGPhotos
import SwiftUI

struct WeatherDetailEditor: View {
    let editController: EditController
    let model: WeatherModel
    
#if os(macOS)
    @Environment(\.openWindow) private var openWindow
#endif
    @Environment(WeatherRoot.self) private var root
        
    var body: some View {
        @Bindable var model = model
        DetailEditor(editController: editController) {
            HeaderEditor(editController: editController)
            
            PhotoSelectionEditor(editController: editController)
            
            WeatherSectionEditor(editController: editController)
        } headerView: { size, safeTopMargin, isInline in
            WeatherEditHeader(editController: editController, size: size, topMargin: safeTopMargin, inline: isInline)
#if !os(macOS)
                .ignoresSafeArea(.container, edges: .top)
#endif
                .id(model.id)
//        } extHeaderView: { dismiss in
//            WeatherViewer(model: model, size: CGSize(width: screenSize.size.width, height: screenSize.size.height), useGame: true)
//                .onTapGesture {
//                    dismiss()
//                }
        } heightCalculator: { size in
            (144, min(size.height * 0.35, 400))
        }
                
        .focusedSceneValue(\.selectedWeather, $model.id)
    }
}

#Preview {
    WeatherDetailEditor(editController: .preview, model: .snow)
        .environment(WeatherRoot.previewWithData)
        .environment(ListModel.preview)
        .environment(SelectionSheetLinkModel())
}
