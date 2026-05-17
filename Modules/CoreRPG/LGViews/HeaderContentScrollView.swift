// @copyright André Trettin

import SwiftUI

@Observable @MainActor
final class HeaderScrollModel {
    var headerOffset: CGFloat = 0
    var headerSize: CGFloat = 0
    var scrollUp: Bool = false
}

struct HeaderContentScrollView<Header: View, Content: View>: View {
    let model: HeaderScrollModel
    let header: Header
    let content: Content
    let backgroundColor: Color
    let scrollThreshold: CGFloat
    let animation: Animation
    let disableHideHeader: Bool
    
    init(
        model: HeaderScrollModel,
        backgroundColor: Color,
        scrollThreshold: CGFloat = 20,
        animation: Animation = .easeInOut(duration: 0.2),
        disableHideHeader: Bool = false,
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content
    ) {
        self.model = model
        self.backgroundColor = backgroundColor
        self.scrollThreshold = scrollThreshold
        self.animation = animation
        self.disableHideHeader = disableHideHeader
        self.header = header()
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity)
            .scrollBounceBehavior(.basedOnSize)
            .applyIf(!disableHideHeader) {
                $0.onScrollGeometryChange(for: CGFloat.self) {
                    max($0.contentOffset.y + $0.contentInsets.top, 0)
                } action: { oldValue, newValue in
                    handleScrollChange(oldValue: oldValue, newValue: newValue)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                headerView
            }
    }
    
    @inline(__always)
    private func handleScrollChange(oldValue: CGFloat, newValue: CGFloat) {
        // If disableHideHeader is enabled, don't process scroll changes
        guard !disableHideHeader else {
            return
        }
        
        let scrollDelta = newValue - oldValue
        
        guard abs(scrollDelta) > scrollThreshold else {
            return
        }
        
        let isScrollingDown = scrollDelta > 0
        
        guard model.scrollUp != isScrollingDown else {
            return
        }
        
        model.scrollUp = isScrollingDown
        let targetOffset = isScrollingDown ? model.headerSize : 0
        
        guard model.headerOffset != targetOffset else {
            return
        }
        
        withAnimation(animation) {
            model.headerOffset = targetOffset
        }
    }

    @ViewBuilder
    private var headerView: some View {
        header
            .onGeometryChange(for: CGFloat.self) {
                $0.size.height
            } action: { _, newValue in
                let sizeDifference = abs(model.headerSize - newValue)
                guard sizeDifference > 0.5 else { return }
                model.headerSize = newValue
            }
            .offset(y: -model.headerOffset)
            .clipped()
            .background {
                backgroundColor
                    .ignoresSafeArea()
                    .offset(y: -model.headerOffset)
            }
    }
}

#Preview {
    @Previewable @State var model = HeaderScrollModel()

    HeaderContentScrollView(
        model: model,
        backgroundColor: .orange
    ) {
        HStack(spacing: 15) {
            Button {
                print("Back button tapped")
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay {
            Text("Apple Store")
                .fontWeight(.semibold)
        }
        .padding(15)
    } content: {
        Group {
#if os(macOS)
            ScrollView {
                Form {
                    VStack(spacing: 15) {
                        ForEach(1...30, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 15)
                                .fill(.gray.opacity(0.35))
                                .frame(height: 50)
                        }
                    }
                    .padding(15)
                }
            }
#else
            Form {
                VStack(spacing: 15) {
                    ForEach(1...30, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 15)
                            .fill(.gray.opacity(0.35))
                            .frame(height: 50)
                    }
                }
                .padding(15)
            }
#endif
        }
    }
}
