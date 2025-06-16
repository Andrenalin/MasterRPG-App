// @copyright André Trettin

import AndrenalinKit
import RPGPhotos
import SwiftUI

struct WeatherDetailEditor: View {
    let editController: EditController
    let model: WeatherModel
    
    @Environment(WeatherRoot.self) private var root

    @State private var detailHeaderModel = DetailHeaderModel(minHeight: 144, maxHeight: 400, maxHeightFromScreenHeight: true)
    @State private var externalHeaderModel = ExternalHeaderModel()

    var body: some View {
        @Bindable var model = model
        DetailEditor(editController: editController) {
            HeaderEditor(editController: editController)
            
            PhotoSelectionEditor(editController: editController)
            
            WeatherSectionEditor(editController: editController)
        } headerView: {
            WeatherEditHeader(editController: editController)
#if !os(macOS)
                .ignoresSafeArea(.container, edges: .top)
#endif
                .id(model.id)
        }
        .focusedSceneValue(\.selectedWeather, $model.id)
        .environment(detailHeaderModel)
        .environment(externalHeaderModel)
    }
}

#Preview {
    WeatherDetailEditor(editController: .preview, model: .snow)
        .environment(WeatherRoot.previewWithData)
        .environment(ListModel.preview)
        .environment(SelectionSheetLinkModel())
}
