// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

struct ViewerRootView: View {
    init(model: ItemDataModel, dismissAction: (() -> Void)? = nil) {
        self.model = model
        self.dismissAction = dismissAction
    }
    
    let model: ItemDataModel
    let dismissAction: (() -> Void)?
    
    @Environment(WeatherRootModel.self) private var root
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
        
    var body: some View {
        let _ = Self._printChanges()
        NavigationStack {
            VStack {
                GeometryReader { proxy in
                    if let weatherModel {
                        WeatherViewer(model: weatherModel, size: proxy.size, useGame: false)
                            .id(model.id)
                    }
                }
            }
            .ignoresSafeArea(.container, edges: [.top, .bottom])
            .overlay(alignment: .topTrailing) {
                //                GlassEffectContainerView {
                //                    SelectionBar(editController: root.editController, model: model, searchModel: searchModel, withoutBookmark: withoutBookmark)
                //                }
            }
            .overlay(alignment: .bottomTrailing) {
                //                GlassEffectContainerView {
                //                    SearchBar(searchModel: searchModel)
                //                }
            }
#if !os(macOS)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    closeButton
                }
            }
#endif
#if !os(visionOS)
            .background(colorScheme == .dark ? Color.black.ignoresSafeArea() : Color.white.ignoresSafeArea())
#endif
            .navigationTitle(Text(model.name))
#if !os(macOS) && !os(tvOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
        }
        .environment(CacheItemListModel())
    }
}

private extension ViewerRootView {
    var weatherModel: WeatherDataModel? {
        root.itemController.model(for: model.id)
    }
    
    var closeButton: some View {
        Button {
            if let dismissAction {
                dismissAction()
            } else {
                dismiss()
            }
        } label: {
            Image(systemName: "xmark.circle")
        }
        //.opacity(showGame ? 0 : 1)
    }
}

#Preview(traits: .mockData) {
    @Previewable @Query var models: [ItemDataModel]
        
    ViewerRootView(model: models[0])
#if os(macOS)
        .frame(width: 800, height: 600)
#endif
}
