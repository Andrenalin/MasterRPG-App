// @copyright André Trettin

import CoreGraphics
import Foundation

struct DragTapClassifier {
    private struct PendingTap {
        let timestamp: TimeInterval
        let location: CGPoint
    }

    private var pendingTap: PendingTap?

    mutating func registerRelease(
        at location: CGPoint,
        timestamp: TimeInterval,
        didDrag: Bool,
        didMagnify: Bool,
        maximumInterval: TimeInterval,
        maximumDistance: CGFloat
    ) -> Bool {
        guard !didDrag, !didMagnify else {
            cancelPendingTap()
            return false
        }

        let currentTap = PendingTap(timestamp: timestamp, location: location)
        guard let pendingTap else {
            self.pendingTap = currentTap
            return false
        }

        let interval = timestamp - pendingTap.timestamp
        let distance = hypot(
            location.x - pendingTap.location.x,
            location.y - pendingTap.location.y
        )
        let isDoubleTap = interval >= 0
            && interval <= max(0, maximumInterval)
            && distance <= max(0, maximumDistance)

        self.pendingTap = isDoubleTap ? nil : currentTap
        return isDoubleTap
    }

    mutating func cancelPendingTap() {
        pendingTap = nil
    }
}

#if !os(tvOS)

    import SwiftUI

    public extension View {
        func dragTapGesture(
            isActive: Bool = true,
            isPressed: Binding<Bool>? = nil,
            pressAction: DragTapGestureViewModifier.Action? = nil,
            releaseAction: DragTapGestureViewModifier.Action? = nil,
            longPressDelay: TimeInterval = DragTapGestureViewModifier.longPressDelay,
            longPressAction: DragTapGestureViewModifier.Action? = nil,
            doubleTapTimeout: TimeInterval = DragTapGestureViewModifier.doubleTapTimeout,
            doubleTapSpatialThreshold: CGFloat = DragTapGestureViewModifier.doubleTapSpatialThreshold,
            doubleTapAction: DragTapGestureViewModifier.Action? = nil,
            dragStartAction: DragTapGestureViewModifier.DragAction? = nil,
            dragAction: DragTapGestureViewModifier.DragAction? = nil,
            dragEndAction: DragTapGestureViewModifier.DragAction? = nil,
            endAction: DragTapGestureViewModifier.Action? = nil,
            magnifierAction: DragTapGestureViewModifier.MagnifierAction? = nil
        ) -> some View {
            modifier(DragTapGestureViewModifier(
                isActive: isActive,
                isPressed: isPressed,
                pressAction: pressAction,
                releaseAction: releaseAction,
                longPressDelay: longPressDelay,
                longPressAction: longPressAction,
                doubleTapTimeout: doubleTapTimeout,
                doubleTapSpatialThreshold: doubleTapSpatialThreshold,
                doubleTapAction: doubleTapAction,
                dragStartAction: dragStartAction,
                dragAction: dragAction,
                dragEndAction: dragEndAction,
                endAction: endAction,
                magnifierAction: magnifierAction
            ))
        }
    }

    public struct DragTapGestureViewModifier: ViewModifier {
        public static let doubleTapTimeout = 0.3
        public static let doubleTapSpatialThreshold: CGFloat = 44
        public static let longPressDelay = 1.0

        public init(
            isActive: Bool = true,
            isPressed: Binding<Bool>? = nil,
            pressAction: Action? = nil,
            releaseAction: Action? = nil,
            longPressDelay: TimeInterval = DragTapGestureViewModifier.longPressDelay,
            longPressAction: Action? = nil,
            doubleTapTimeout: TimeInterval = DragTapGestureViewModifier.doubleTapTimeout,
            doubleTapSpatialThreshold: CGFloat = DragTapGestureViewModifier.doubleTapSpatialThreshold,
            doubleTapAction: Action? = nil,
            dragStartAction: DragAction? = nil,
            dragAction: DragAction? = nil,
            dragEndAction: DragAction? = nil,
            endAction: Action? = nil,
            magnifierAction: MagnifierAction? = nil
        ) {
            self.isActive = isActive
            isPressedBinding = isPressed ?? .constant(false)
            self.pressAction = pressAction
            self.releaseAction = releaseAction
            self.longPressDelay = longPressDelay
            self.longPressAction = longPressAction
            self.doubleTapTimeout = doubleTapTimeout
            self.doubleTapSpatialThreshold = doubleTapSpatialThreshold
            self.doubleTapAction = doubleTapAction
            self.dragStartAction = dragStartAction
            self.dragAction = dragAction
            self.dragEndAction = dragEndAction
            self.endAction = endAction
            self.magnifierAction = magnifierAction
        }

        public typealias Action = @MainActor (DragGesture.Value) -> Void
        public typealias DragAction = @MainActor (DragGesture.Value) -> Void
        public typealias MagnifierAction = @MainActor (MagnifyGesture.Value, Bool) -> Void

        private static let dragActivationThreshold: CGFloat = 3

        private var isPressedBinding: Binding<Bool>

        private let isActive: Bool
        private let pressAction: Action?
        private let releaseAction: Action?
        private let longPressDelay: TimeInterval
        private let longPressAction: Action?
        private let doubleTapTimeout: TimeInterval
        private let doubleTapSpatialThreshold: CGFloat
        private let doubleTapAction: Action?
        private let dragStartAction: DragAction?
        private let dragAction: DragAction?
        private let dragEndAction: DragAction?
        private let endAction: Action?
        private let magnifierAction: MagnifierAction?

        @State private var didDrag = false
        @State private var didLongPress = false
        @State private var didMagnify = false
        @State private var isMagnifying = false
        @State private var isPressed = false
        @State private var lastDragValue: DragGesture.Value?
        @State private var longPressTask: Task<Void, Never>?
        @State private var tapClassifier = DragTapClassifier()

        public func body(content: Content) -> some View {
            if isActive {
                content
                    .gesture(gesture)
                    .onChange(of: isPressed) { _, newValue in
                        isPressedBinding.wrappedValue = newValue
                    }
                    .onDisappear(perform: cancelGesture)
            } else {
                content
            }
        }
    }

    private extension DragTapGestureViewModifier {
        typealias CombinedGesture = SimultaneousGesture<MagnifyGesture, DragGesture>

        var gesture: some Gesture {
            MagnifyGesture(minimumScaleDelta: 0)
                .simultaneously(with: DragGesture(minimumDistance: 0, coordinateSpace: .local))
                .onChanged(gestureChanged(_:))
                .onEnded(gestureEnded(_:))
        }

        func gestureChanged(_ value: CombinedGesture.Value) {
            if let magnifyValue = value.first {
                let isFirstValue = !isMagnifying
                if isFirstValue {
                    isMagnifying = true
                    didMagnify = true
                    tapClassifier.cancelPendingTap()
                    cancelLongPress()
                }
                magnifierAction?(magnifyValue, isFirstValue)
            }

            guard let dragValue = value.second else { return }
            lastDragValue = dragValue
            guard !isMagnifying else { return }

            tryHandlePress(dragValue)
            tryHandleDragging(dragValue)
        }

        func gestureEnded(_ value: CombinedGesture.Value) {
            let finalDragValue = value.second ?? lastDragValue
            if let finalDragValue {
                tryHandleRelease(finalDragValue)
            } else {
                cancelLongPress()
            }

            isMagnifying = false
            didMagnify = false
            lastDragValue = nil
        }
    }

    private extension DragTapGestureViewModifier {
        func tryHandlePress(_ value: DragGesture.Value) {
            guard !isPressed else { return }
            isPressed = true
            didLongPress = false
            pressAction?(value)
            triggerLongPressAfterDelay(value)
        }

        func tryHandleDragging(_ value: DragGesture.Value) {
            guard !didDrag else {
                dragAction?(value)
                return
            }

            let horizontalDistance = abs(value.location.x - value.startLocation.x)
            let verticalDistance = abs(value.location.y - value.startLocation.y)
            guard horizontalDistance >= Self.dragActivationThreshold
                    || verticalDistance >= Self.dragActivationThreshold else { return }

            didDrag = true
            tapClassifier.cancelPendingTap()
            cancelLongPress()
            dragStartAction?(value)
        }

        func tryHandleRelease(_ value: DragGesture.Value) {
            guard isPressed else {
                cancelLongPress()
                return
            }

            let draggedBeforeRelease = didDrag || didLongPress
            let magnifiedBeforeRelease = didMagnify
            let isDoubleTap = tapClassifier.registerRelease(
                at: value.location,
                timestamp: value.time.timeIntervalSinceReferenceDate,
                didDrag: draggedBeforeRelease,
                didMagnify: magnifiedBeforeRelease,
                maximumInterval: doubleTapTimeout,
                maximumDistance: doubleTapSpatialThreshold
            )

            cancelLongPress()
            isPressed = false
            didDrag = false
            didLongPress = false

            if isDoubleTap {
                doubleTapAction?(value)
            }
            dragEndAction?(value)
            releaseAction?(value)
            endAction?(value)
        }

        func triggerLongPressAfterDelay(_ value: DragGesture.Value) {
            cancelLongPress()
            guard let longPressAction else { return }

            let delay = max(0, longPressDelay)
            longPressTask = Task { @MainActor in
                do {
                    try await Task.sleep(for: .seconds(delay))
                } catch {
                    return
                }

                guard !Task.isCancelled, isPressed, !didDrag, !didMagnify else { return }
                didLongPress = true
                tapClassifier.cancelPendingTap()
                longPressAction(value)
            }
        }

        func cancelLongPress() {
            longPressTask?.cancel()
            longPressTask = nil
        }

        func cancelGesture() {
            cancelLongPress()
            tapClassifier.cancelPendingTap()
            isPressed = false
            isPressedBinding.wrappedValue = false
            didDrag = false
            didLongPress = false
            didMagnify = false
            isMagnifying = false
            lastDragValue = nil
        }
    }

#endif
