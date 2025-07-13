        if #available(iOS 26.0, *) {
            Button {
                isEditing = true
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.glass)
        } else {
            Button {
                isEditing = true
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.imageOverlay)
        }
