// @copyright André Trettin

import SwiftUI

@MainActor @Observable
final class HeaderFooterScrollModel {
    var headerOffset: CGFloat = 0
    var footerOffset: CGFloat = 0
    var headerSize: CGFloat = 0
    var footerSize: CGFloat = 0
    
    var scrollUp: Bool = false
}

struct HeaderFooterContentScrollView<Header: View, Content: View, Footer: View, Background: View>: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    init(model: HeaderFooterScrollModel, @ViewBuilder header: () -> Header, @ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer, @ViewBuilder background: () -> Background) {
        self.model = model
        self.header = header()
        self.content = content()
        self.footer = footer()
        self.background = background()
    }
    
    let model: HeaderFooterScrollModel
    
    @ViewBuilder var header: Header
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer
    @ViewBuilder var background: Background
    
    var body: some View {
        //let _ = Self.printViewChangesOnlyInDebug()
        
        content
            .frame(maxWidth: .infinity)
            .scrollBounceBehavior(.basedOnSize)
            .onScrollGeometryChange(for: CGFloat.self) {
                max($0.contentOffset.y + $0.contentInsets.top, 0)
            } action: { oldValue, newValue in
                let direction = (newValue - oldValue) > 0 ? true : false
                if abs(newValue - oldValue) > 20 && model.scrollUp != direction {
                    model.scrollUp = direction
                    withAnimation(accessibilityReduceMotion ? nil : .easeInOut(duration: 0.2)) {
                        if model.scrollUp {
                            model.headerOffset = model.headerSize
                            model.footerOffset = model.footerSize
                        } else {
                            model.headerOffset = 0
                            model.footerOffset = 0
                        }
                    }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                headerView
            }
            .safeAreaInset(edge: .bottom, spacing: -model.footerOffset) {
                footerView
            }
    }
    
    @ViewBuilder
    private var headerView: some View {
        VStack(spacing: 0) {
            header
                .onGeometryChange(for: CGFloat.self) {
                    $0.size.height
                } action: { newValue in
                    model.headerSize = newValue
                }
        }
        .offset(y: -model.headerOffset)
        .clipped()
        .background {
            background
                .ignoresSafeArea()
                .offset(y: -model.headerOffset)
        }
    }
    
    @ViewBuilder
    private var footerView: some View {
        VStack(spacing: 0) {
            footer
                .onGeometryChange(for: CGFloat.self) {
                    $0.size.height
                } action: { newValue in
                    model.footerSize = newValue
                }
        }
        .offset(y: +model.footerOffset)
        .clipped()
        .background {
            background
                .rotationEffect(Angle(degrees: 180))
                .ignoresSafeArea()
                .offset(y: +model.footerOffset)
        }
    }
}

#Preview {
    @Previewable @State var model = HeaderFooterScrollModel()
    
    HeaderFooterContentScrollView(model: model) {
        HStack(spacing: 15) {
            Button {
                
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay {
            Text(verbatim: "Apple Store")
                .font(.headline)
        }
        .padding(15)
    } content: {
        Group {
#if os(macOS)
            ScrollView {
                Form {
                    VStack(spacing: 15) {
                        ForEach(1...100, id: \.self) { _ in
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
                    ForEach(1...100, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 15)
                            .fill(.gray.opacity(0.35))
                            .frame(height: 50)
                    }
                }
                .padding(15)
            }
#endif
        }.overlay(alignment: .bottom) {
            Text(verbatim: "Bottom")
                .padding()
                //.glassEffect(.regular.interactive())
                .padding(120)
        }
    } footer: {
        VStack {
            Label {
                Text(verbatim: "Mage")
                    .font(.largeTitle)
            } icon: {
                Image(systemName: "gear")
                    .font(.largeTitle)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 128)
} background: {
        Rectangle().fill(Color.orange.gradient)
    }
    .overlay(alignment: .bottom) {
        Text(verbatim: "Bottom")
            .padding()
            //.glassEffect(.regular.interactive())
            .safeAreaInset(edge: .bottom) {
                VStack {
                    Label {
                        Text(verbatim: "Mage")
                            .font(.largeTitle)
                    } icon: {
                        Image(systemName: "gear")
                            .font(.largeTitle)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 128)
                .opacity(0)
            }
    }
}
