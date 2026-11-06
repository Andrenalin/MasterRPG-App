// @copyright André Trettin

import SwiftUI

/// The thumbnail slot of an entry that has no image to show (a map room without coordinates):
/// same size as `ThumbnailRowPhotoView`, so the rest of the row keeps its place. The symbol says
/// what is missing (a player row uses a person or an eye). See CODE_AUDIT_24 §8.2.
public struct ThumbnailRowEmptyView: View {
    public init(listDisplayModel: ListDisplayModel, systemImage: String = "square.dashed") {
        self.listDisplayModel = listDisplayModel
        self.systemImage = systemImage
    }

    let listDisplayModel: ListDisplayModel
    let systemImage: String

    public var body: some View {
        Image(systemName: systemImage)
            .font(.title2)
            .foregroundStyle(.secondary)
            .frame(width: listDisplayModel.imageHeight, height: listDisplayModel.imageHeight)
            .background(Color.accentColor.tertiary, in: .rect(cornerRadius: ResolvedAppTheme.elementCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: ResolvedAppTheme.elementCornerRadius, style: .continuous)
                    .stroke(Color.accentColor.secondary, lineWidth: 2)
            }
            .accessibilityHidden(true)
    }
}

#Preview {
    ThumbnailRowEmptyView(listDisplayModel: ListDisplayModel())
        .padding()
}
