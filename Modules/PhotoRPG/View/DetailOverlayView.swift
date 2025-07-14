// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI

struct DetailOverlayView: View {
    let model: PhotoDataModel
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(model.name)
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            HStack {
                TagItemRow(tags: [model.category.title])
                
                TagItemRow(tags: model.tags)
            }
            Text(model.information)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(.primary)
                .opacity(0.8)
        }
    }
}

#Preview(traits: .mockData) {
    @Previewable @Query var photos: [PhotoDataModel]
    DetailOverlayView(model: photos[0])
}
