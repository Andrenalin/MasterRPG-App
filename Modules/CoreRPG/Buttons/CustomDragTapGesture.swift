// @copyright André Trettin

#if !os(tvOS)

    import SwiftUI

    public extension View {
            func dragTapGesture(isActive: Bool = true,
                            isPressed: Binding<Bool>? = nil,
                            pressAction: DragTapGestureViewModifier.Action? = nil,
                            releaseAction: DragTapGestureViewModifier.Action? = nil,
                            longPressDelay: TimeInterval = DragTapGestureViewModifier.longPressDelay,
                            longPressAction: DragTapGestureViewModifier.Action? = nil,
                            doubleTapTimeout: TimeInterval = DragTapGestureViewModifier.doubleTapTimeout,
                            doubleTapAction: DragTapGestureViewModifier.Action? = nil,
                            dragStartAction: DragTapGestureViewModifier.DragAction? = nil,
                            dragAction: DragTapGestureViewModifier.DragAction? = nil,
                            dragEndAction: DragTapGestureViewModifier.DragAction? = nil,
                            endAction: DragTapGestureViewModifier.Action? = nil,
                            magnifierAction: DragTapGestureViewModifier.MagnifierAction? = nil) -> some View
        {
            modifier(DragTapGestureViewModifier(isActive: isActive, isPressed: isPressed, pressAction: pressAction, releaseAction: releaseAction, longPressDelay: longPressDelay, longPressAction: longPressAction, doubleTapTimeout: doubleTapTimeout, doubleTapAction: doubleTapAction, dragStartAction: dragStartAction, dragAction: dragAction, dragEndAction: dragEndAction, endAction: endAction, magnifierAction: magnifierAction))
        }
    }

    public struct DragTapGestureViewModifier: ViewModifier {
        public static let doubleTapTimeout = 0.3
        public static let longPressDelay = 1.0
        public init(isActive: Bool = true,
                    isPressed: Binding<Bool>? = nil,
                    pressAction: Action? = nil,
                    releaseAction: Action? = nil,
                    longPressDelay: TimeInterval = DragTapGestureViewModifier.longPressDelay,
                    longPressAction: Action? = nil,
                    doubleTapTimeout: TimeInterval = DragTapGestureViewModifier.doubleTapTimeout,
                    doubleTapAction: Action? = nil,
                    dragStartAction: DragAction? = nil,
                    dragAction: DragAction? = nil,
                    dragEndAction: DragAction? = nil,
                    endAction: Action? = nil,
                    magnifierAction: MagnifierAction? = nil)
        {
            self.isActive = isActive
            isPressedBinding = isPressed ?? .constant(false)
            self.pressAction = pressAction
            self.releaseAction = releaseAction
            self.longPressDelay = longPressDelay
            self.longPressAction = longPressAction
            self.doubleTapTimeout = doubleTapTimeout
            self.doubleTapAction = doubleTapAction
            self.dragStartAction = dragStartAction
            self.dragAction = dragAction
            self.dragEndAction = dragEndAction
            self.endAction = endAction
            self.magnifierAction = magnifierAction
        }

        public typealias Action = (DragGesture.Value) -> Void
        public typealias DragAction = (DragGesture.Value) -> Void
        public typealias MagnifierAction = (CGFloat, Bool) -> Void

        var isPressedBinding: Binding<Bool>

        let isActive: Bool
        let pressAction: Action?
        let releaseAction: Action?
        let longPressDelay: TimeInterval
        let longPressAction: Action?
        let doubleTapTimeout: TimeInterval
        let doubleTapAction: Action?
        let dragStartAction: DragAction?
        let dragAction: DragAction?
        let dragEndAction: DragAction?
        let endAction: Action?
        let magnifierAction: MagnifierAction?

        @State private var isDraggingStarts = false
        @State private var isPressed = false
        @State private var longPressDate = Date()
        @State private var releaseDate = Date()
        @State private var lastValue: DragGesture.Value?

        @GestureState private var isMagnifying = false
        @GestureState private var isDragging = false

        public func body(content: Content) -> some View {
            if isActive {
                content                    
                    .gesture(gesture)
                    .onChange(of: isPressed) {
                        isPressedBinding.wrappedValue = isPressed
                    }
                    .onChange(of: isDragging) {
                        if !isDragging, let lastValue {
                            tryHandleRelease(lastValue)
                        }
                    }
            } else {
                content
            }
        }
    }

    private extension DragTapGestureViewModifier {
        var gesture: some Gesture {
            let magni = MagnificationGesture().updating($isMagnifying) { value, state, _ in
                let firstValue = !state
                Task {
                    magnifierAction?(value, firstValue)
                }
                state = true
            }

            let drag = DragGesture(minimumDistance: 0).updating($isDragging) { value, state, _ in
                guard !isMagnifying else {
                    Task {
                        lastValue = value
                    }
                    return
                }
                Task {
                    tryHandlePress(value)
                    tryHandleDragging(value)
                    lastValue = value
                }
                state = true
            }
            return magni.simultaneously(with: drag)
        }
    }

    private extension DragTapGestureViewModifier {
        func tryHandlePress(_ value: DragGesture.Value) {
            guard !isPressed else { return }
            isPressed = true
            pressAction?(value)
            tryTriggerLongPressAfterDelay(value)
        }

        func tryHandleDragging(_ value: DragGesture.Value) {
            guard !isDraggingStarts else {
                dragAction?(value)
                return
            }
            let absX = abs(value.startLocation.x - value.location.x)
            let absY = abs(value.startLocation.y - value.location.y)
            if absX >= 3 || absY >= 3 {
                isDraggingStarts = true
                longPressDate = Date()
                dragStartAction?(value)
            }
        }

        func tryHandleRelease(_ value: DragGesture.Value) {
            guard isPressed else { return }
            isPressed = false
            isDraggingStarts = false
            longPressDate = Date()
            releaseDate = tryTriggerDoubleTap(value) ? .distantPast : Date()
            dragEndAction?(value)
            releaseAction?(value)
            endAction?(value)
        }

        func tryTriggerLongPressAfterDelay(_ value: DragGesture.Value) {
            guard let action = longPressAction else { return }
            let date = Date()
            longPressDate = date
            let delay = longPressDelay
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard self.longPressDate == date else { return }
                action(value)
            }
        }

        func tryTriggerDoubleTap(_ value: DragGesture.Value) -> Bool {
            let interval = Date().timeIntervalSince(releaseDate)
            let isDoubleTap = interval < doubleTapTimeout
            if isDoubleTap { doubleTapAction?(value) }
            return isDoubleTap
        }
    }

#endif
