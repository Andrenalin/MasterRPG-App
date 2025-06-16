// @copyright André Trettin

import SwiftUI

@MainActor @Observable
public final class DetailHeaderModel {
    public init(size: CGSize = CGSize(width: 320, height: 150), topSafeAreaHeight: CGFloat = 60, isInline: Bool = false) {
        self.size = size
        self.topSafeAreaHeight = topSafeAreaHeight
        self.isInline = isInline
    }
    public var size: CGSize
    public var topSafeAreaHeight: CGFloat
    public var isInline: Bool
}

@MainActor @Observable
public final class ExternalHeaderModel {
    public init(showExtHeader: Bool = false) {
        self.showExtHeader = showExtHeader
    }
    public var showExtHeader: Bool
}

public struct DetailEditor<Content: View, ExtContent: View, Header: View, ExtentedHeader: View>: View {
    public init(editController: any EditControllable, @ViewBuilder contentView: () -> Content, @ViewBuilder headerView: () -> Header, @ViewBuilder extHeaderView: () -> ExtentedHeader, @ViewBuilder extContentView: () -> ExtContent = EmptyView.init, extContentHeight: @escaping (CGFloat) -> CGFloat, heightCalculator: @escaping (CGSize) -> (CGFloat, CGFloat)) {
        self.editController = editController
        self.contentView = contentView()
        self.headerView = headerView()
        self.extHeaderView = extHeaderView()
        self.hasExtHeaderView = true
        self.extContentView = extContentView()
        self.extContentHeight = extContentHeight
        self.heightCalculator = heightCalculator
    }
    
    public init(editController: any EditControllable, @ViewBuilder contentView: @escaping () -> Content, @ViewBuilder headerView: () -> Header, @ViewBuilder extContentView: () -> ExtContent = EmptyView.init, extContentHeight: @escaping (CGFloat) -> CGFloat, heightCalculator: @escaping (CGSize) -> (CGFloat, CGFloat)) where ExtentedHeader == EmptyView  {
        self.editController = editController
        self.contentView = contentView()
        self.headerView = headerView()
        self.extHeaderView = { EmptyView() }()
        self.hasExtHeaderView = false
        self.extContentView = extContentView()
        self.extContentHeight = extContentHeight
        self.heightCalculator = heightCalculator
    }
    
    public init(editController: any EditControllable, @ViewBuilder contentView: () -> Content, @ViewBuilder headerView: () -> Header, @ViewBuilder extHeaderView: () -> ExtentedHeader, heightCalculator: @escaping (CGSize) -> (CGFloat, CGFloat)) where ExtContent == EmptyView {
        self.editController = editController
        self.contentView = contentView()
        self.headerView = headerView()
        self.extHeaderView = extHeaderView()
        self.hasExtHeaderView = true
        self.extContentView = { EmptyView() }()
        self.extContentHeight = { $0 }
        self.heightCalculator = heightCalculator
    }
    
    public init(editController: any EditControllable, @ViewBuilder contentView: () -> Content, @ViewBuilder headerView: () -> Header, heightCalculator: @escaping (CGSize) -> (CGFloat, CGFloat)) where ExtContent == EmptyView, ExtentedHeader == EmptyView {
        self.editController = editController
        self.contentView = contentView()
        self.headerView = headerView()
        self.extHeaderView = { EmptyView() }()
        self.hasExtHeaderView = false
        self.extContentView = { EmptyView() }()
        self.extContentHeight = { $0 }
        self.heightCalculator = heightCalculator
    }
    
    let editController: any EditControllable
    let contentView: Content
    let headerView: Header
    let extHeaderView: ExtentedHeader
    let hasExtHeaderView: Bool
    let extContentView: ExtContent
    let extContentHeight: (CGFloat) -> CGFloat
    let heightCalculator: (CGSize) -> (CGFloat, CGFloat)
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(ListModel.self) private var itemListModel
    @Environment(\.itemSplitViewSizeMode) private var sizemode
    @Environment(\.wideMode) private var widemode
    
#if os(iOS) || os(visionOS)
    @State private var editMode: EditMode = .inactive
#endif
    
    @State private var scrollPositionY: CGFloat = 0
    
    @State private var keyBoardShown = false

    @State private var detailHeaderModel = DetailHeaderModel()
    @State private var inlineDetailHeaderModel = DetailHeaderModel(isInline: true)
    @State private var externalHeaderModel = ExternalHeaderModel()

    public var body: some View {
        let _ = Self._printChanges()
        GeometryReader { geometry in
            @Bindable var editorModel = editController.editorModel
            
            ScrollViewReader { scrollProxy in
                Group {
#if os(macOS)
                    ScrollView {
                        formContent(geometry: geometry)
                            .padding(.trailing, 12)
                            .padding(.top, 8)
                    }
#else
                    formContent(geometry: geometry)
#endif
                }
                .padding([.leading, .top, .bottom], valueFor(iOS: 0, macOS: 8, tvOS: 0, visionOS: 0))
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentOffset.y.rounded()
                } action: { oldValue, newValue in
#if os(macOS)
                    guard newValue >= 0 else { return }
                    scrollPositionY = newValue
#else
                    scrollPositionY = newValue
                    updateDetailHeaderModel(geometry: geometry)
                    updateInlineDetailHeaderModel(geometry: geometry)
#endif
                }
                .scrollIndicatorsFlash(onAppear: true)
                .scrollIndicatorsFlash(trigger: entryCounter)
                .scrollBounceBehavior(.basedOnSize)
#if os(macOS)
                .safeAreaInset(edge: .top, spacing: 0) {
                    headerContent(geometry: geometry)
                        .padding(.horizontal, 12)
                }
#else
                .overlay(alignment: .top) {
                    headerContent(geometry: geometry)
                        .opacity(keyBoardShown ? 0 : 1)
                }
#endif
                .onChange(of: itemListModel.selectedItem, initial: true) {
                    update(scrollProxy: scrollProxy)
                }
                .onChange(of: itemListModel.scrollEntryId) {
                    guard let id = itemListModel.scrollEntryId else { return }
                    Task {
                        try? await Task.sleep(for: .seconds(0.15))
                        withAnimation { scrollProxy.scrollTo(id, anchor: .center) }
                        itemListModel.scrollEntryId = nil
                    }
                }
            }
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
            .applyIf(UIDevice.current.userInterfaceIdiom == .phone) {
                $0.navigationBarBackButtonHidden(true)
            }
#endif
#if os(iOS) || os(visionOS)
            .environment(\.editMode, $editMode)
            .ignoresSafeArea(.container, edges: .top)
            .onChange(of: editorModel.activateDetailEditMode, initial: true) {
                withAnimation { editMode <=> editorModel.activateDetailEditMode ? .active : .inactive }
            }
#endif
            .userActivity(UserActivity.bundleIdentifierType) { userActivity in
                UserActivity.addPayLoad(for: userActivity, title: "\(itemListModel.listTitleName): \(name))", module: editController.itemControllable.itemDataModel.networkModule, itemId: editorModel.currentListItem?.model.itemId ?? UUID(), childId: nil)
            }
            .overlay(alignment: .bottom) {
                if externalHeaderModel.showExtHeader {
                    extHeaderView
                        .background(.background)
                        .shadow(radius: 8)
                        .frame(height: geometry.size.height + geometry.safeAreaInsets.top - headerHeight(geometry: geometry))
                        .transition(.move(edge: .bottom))
                }
            }
            .animation(.spring(duration: 0.5).delay(0.15), value: externalHeaderModel.showExtHeader)
            .onKeyboardShow { isShown in
                withAnimation { keyBoardShown = isShown }
            }
        }
    }
}

private extension DetailEditor {
    @ViewBuilder
    func formContent(geometry: GeometryProxy) -> some View {
        Form {
#if !os(macOS)
            Group {
                if keyBoardShown {
                    headerView
                        .environment(inlineDetailHeaderModel)
                } else {
                    Color.clear
                }
            }
            .frame(height: inlineDetailHeaderModel.size.height)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
#endif
            contentView
        }
        
#if os(macOS)
        Divider()

        extContentView()
            .listRowInsets(.init())
            .frame(maxWidth: .infinity, minHeight: extContentHeight(geometry.size.height), idealHeight: extContentHeight(geometry.size.height) * 1.5,  maxHeight: .infinity)
#endif
    }
    
    @ViewBuilder
    func headerContent(geometry: GeometryProxy) -> some View {
        headerView
            .environment(detailHeaderModel)

            .contentShape(.rect)
#if !os(tvOS)
            .onTapGesture(count: 1) {
                guard hasExtHeaderView else { return }
                externalHeaderModel.showExtHeader.toggle()
            }
#endif
            .frame(height: detailHeaderModel.size.height, alignment: .bottom)
            .background {
                UnevenRoundedRectangle(bottomLeadingRadius: 24, bottomTrailingRadius: 24, style: .continuous)
                    .fill(fillDark())
                    .ignoresSafeArea(.container, edges: .top)
                    .clipShape(.rect(bottomLeadingRadius: 24, bottomTrailingRadius: 24, style: .continuous))
            }
            .overlay(alignment: .topTrailing) {
                HStack {
                    undoButtonView
                    redoButtonView
                }
                .padding(.top, valueFor(iOS: geometry.safeAreaInsets.top + 16, macOS: 40, tvOS: geometry.safeAreaInsets.top + 52, visionOS: 66))
                .padding(.trailing)
            }
#if os(iOS) || os(visionOS)
            .toolbar {
                if (sizemode == .small || widemode == .small) {
                    ToolbarItem(placement: .navigation) {
                        ImageOverlayButton(icon: "chevron.left") {
                            withAnimation {
                                itemListModel.selectedItem = nil
                                itemListModel.selectedItems = []
                            }
                        }
                        .navigationBarBackButtonHidden(true)
                    }
                }
            }
#endif
#if os(visionOS)
            .glassBackgroundEffect(in: .rect(bottomLeadingRadius: 24, bottomTrailingRadius: 24, topTrailingRadius: 48, style: .continuous))
#endif
            .compositingGroup()
            .shadow(color: .primary, radius: 4)
    }
    
    func headerHeight(geometry: GeometryProxy) -> CGFloat {
        let (low, high) = heightCalculator(geometry.size)
        let safeArea = geometry.safeAreaInsets.top
        return max(((high + safeArea) - scrollPositionY), low + safeArea)
    }
        
    func update(scrollProxy: ScrollViewProxy) {
        if let item = itemListModel.selectedItem {
            if editController.editorModel.currentItemId != item.model.itemId || editController.editorModel.currentEntryId != item.model.entryId {
                editController.setCurrentItem(to: item)
                guard let entryId = item.model.entryId else { return }
                Task {
                    try? await Task.sleep(for: .seconds(0.25))
                    withAnimation { scrollProxy.scrollTo(entryId, anchor: .center) }
                }
            }
        } else {
            if editController.editorModel.currentItemId != nil {
                editController.resetCurrentItem(with: "save".localizedString)
            }
        }
    }
    
    var entryCounter: Int {
        (editController as? (any EntryDataEditable))?.editEntries.count ?? 0
    }
    
    var undoButtonView: some View {
        Group {
            ImageOverlayButton(icon: "arrow.uturn.backward") {
                withAnimation { editController.undo() }
            }
            .opacity(editController.canUndo ? 1 : 0)
        }
    }
    
    var redoButtonView: some View {
        Group {
            ImageOverlayButton(icon: "arrow.uturn.forward") {
                withAnimation { editController.redo() }
            }
            .opacity(editController.canRedo ? 1 : 0)
        }
    }
    
    var name: String {
        editController.itemControllable.itemOrEmpty(for: editController.editorModel.currentItemId ?? UUID()).name
    }
    
    func fillDark() -> some ShapeStyle {
#if os(iOS)
        if colorScheme == .dark {
            Color.black
        } else {
            Color.black.opacity(0.7)
        }
#else
        BackgroundStyle.background
#endif
    }

    func updateInlineDetailHeaderModel(geometry: GeometryProxy) {
        let height = heightCalculator(geometry.size).1 + valueFor(iOS: widemode == .small ? 44 : topSafeArea(from: geometry.safeAreaInsets.top), macOS: 0, tvOS: 0, visionOS: 0)
        let offset = CGFloat(valueFor(iOS: 8, macOS: 24, tvOS: 8, visionOS: 8))

        let size = CGSize(width: geometry.size.width - offset, height: height)
        let topSafeAreaHeight = topSafeArea(from: geometry.safeAreaInsets.top)

        inlineDetailHeaderModel.size <=> size
        inlineDetailHeaderModel.topSafeAreaHeight <=> topSafeAreaHeight
    }

    func updateDetailHeaderModel(geometry: GeometryProxy) {
        let height = headerHeight(geometry: geometry) + valueFor(iOS: 0, macOS: 0, tvOS: 0, visionOS: 44)
        let offset = CGFloat(valueFor(iOS: widemode == .small ? 0 : 8, macOS: 24, tvOS: 8, visionOS: 0))

        let size = CGSize(width: geometry.size.width - offset, height: height)
        let topSafeAreaHeight = topSafeArea(from: geometry.safeAreaInsets.top)

        detailHeaderModel.size <=> size
        detailHeaderModel.topSafeAreaHeight <=> topSafeAreaHeight
    }

    func topSafeArea(from height: CGFloat) -> CGFloat {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone ? height : height / 2
        #else
        height
        #endif
    }
}
