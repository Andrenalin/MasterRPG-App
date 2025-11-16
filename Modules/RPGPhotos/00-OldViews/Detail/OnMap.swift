// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct OnMapPin: View {
    init(model: PhotoModel, color: Color, size: CGSize, isDragging: Bool, isSelected: Bool) {
        self.model = model
        self.color = color
        self.size = size
        self.isDragging = isDragging
        self.isSelected = isSelected
    }

    let model: PhotoModel
    let color: Color
    let size: CGSize
    var isDragging: Bool
    var isSelected: Bool

    @Environment(PhotoRootModel.self) private var root

    @State private var image: AKImage?

    var body: some View {
        VStack {
            if let image {
                Image(akImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                color
            }
        }
        .clipShape(Circle())
        .shadow(color: .black, radius: 4, x: 4, y: 4)
        .padding(3)
        .background(isDragging ? .yellow : isSelected ? .red : .gray)
        .clipShape(Circle())
        .frame(width: size.width, height: size.height)
        .onChange(of: model.fileUrl, initial: true) {
            loadThumbnail()
        }
    }

    func loadThumbnail() {
        Task {
            await root.cacheController?.thumbnailId(for: model.id, with: model.fileUrl)
            let newimage = await root.cacheController?.thumbnail(for: model.id)
            withAnimation { image = newimage }
        }
    }
}

#Preview {
    OnMapPin(model: PhotoModel.preview, color: .blue, size: CGSize(width: 66, height: 66), isDragging: false, isSelected: true)
        .environment(PhotoRootModel.preview)
}
