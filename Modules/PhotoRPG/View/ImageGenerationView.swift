// @copyright André Trettin

import ImagePlayground
import SwiftUI

@available(iOS 18.1, *)
struct ImageGenerationView: View {
    @State private var imageDescription = ""
    @State private var isShowingImagePlayground = false
    @State private var imageURL: URL?

    var body: some View {
        VStack(spacing: 20) {
            TextField("Describe an image", text: $imageDescription)
                .textFieldStyle(.roundedBorder)

            Button("Image Playground", systemImage: "apple.image.playground") {
                isShowingImagePlayground = true
            }

            AsyncImage(url: imageURL) { image in
                image
                    .resizable()
                    .scaledToFit()
            } placeholder: {
                Text("(No image)")
            }
        }
        .padding()
        .imagePlaygroundSheet(isPresented: $isShowingImagePlayground, concept: imageDescription) { url in
            if let imageURL {
                try? FileManager.default.removeItem(at: imageURL)
            }

            let newImageURL = URL.documentsDirectory.appending(path: "\(UUID()).png")
            try? FileManager.default.moveItem(at: url, to: newImageURL)
            imageURL = newImageURL
        }
    }
}

#Preview {
    if #available(iOS 18.1, *) {
        ImageGenerationView()
    } else {
        Text("Dead")
    }
}
