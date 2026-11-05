// @copyright André Trettin

import SwiftUI

/// The thumbnail slot of an entry that has no image to show (a map room without coordinates):
/// same size as `ThumbnailRowPhotoView`, so the rest of the row keeps its place.
public struct ThumbnailRowEmptyView: View {
    public init(listDisplayModel: ListDisplayModel) {
        self.listDisplayModel = listDisplayModel
    }

    let listDisplayModel: ListDisplayModel

    public var body: some View {
        Image(systemName: "square.dashed")
            .font(.title2)
            .foregroundStyle(.secondary)
            .frame(width: listDisplayModel.imageHeight, height: listDisplayModel.imageHeight)
            .background(Color.accentColor.tertiary, in: .rect(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.accentColor.secondary, lineWidth: 2)
            }
            .accessibilityHidden(true)
    }
}

#Preview {
    ThumbnailRowEmptyView(listDisplayModel: ListDisplayModel())
        .padding()
}
