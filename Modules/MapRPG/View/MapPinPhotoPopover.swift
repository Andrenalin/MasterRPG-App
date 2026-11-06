// @copyright André Trettin

import CoreRPG
import PhotoRPG
import WeatherRPG
import SwiftUI

// The pin photo popover: a big picture of a pin's photo in the same glass panel as the pin
// action menu (`MapPopover`). It replaces the old "zoom the pin" action: instead of
// enlarging the token on the map, the photo opens next to it.
//
// Two ways to open it:
// - local: a double tap on the pin, on this device only;
// - shared: the game master's "Show Pin Photo" action sets the pin's `isZoom` flag (the field
//   keeps its wire name), and every device that receives the change opens the popover.

/// What a change of a pin's shared photo flag means for the popover on this device.
public enum MapPinPhotoSharing {
    public enum Change: Equatable, Sendable {
        /// The game master started showing the photo: open the popover.
        case show
        /// The game master stopped showing it: close the popover.
        case hide
    }

    /// The reaction to a pin's shared flag going from `wasShared` to `isShared`, `nil` when it
    /// did not change. Only a change counts, so a pin that is already shared when a map opens
    /// (a stale flag from an earlier session) does not pop up by itself.
    public static func change(wasShared: Bool, isShared: Bool) -> Change? {
        guard wasShared != isShared else { return nil }
        return isShared ? .show : .hide
    }

    /// Edge length of the photo at the default text size, large enough to recognize a face
    /// across the table. The popover's views scale it with Dynamic Type.
    public static var photoSide: CGFloat {
#if os(tvOS)
        480
#elseif os(macOS)
        360
#else
        280
#endif
    }
}

/// The popover's content: the pin's photo with its name, Close and, during a game, Full Screen.
struct MapPinPhotoPopoverContent: View {
    let pin: MapPinModel
    /// `nil` hides the Full Screen button: outside a game, or a pin without a photo.
    var onShowFullScreen: (() -> Void)?
    let onClose: () -> Void

    @Environment(MapRootModel.self) private var root

    var body: some View {
        MapPhotoPanel(
            title: pin.name,
            onShowFullScreen: pin.photoId == nil ? nil : onShowFullScreen,
            onClose: onClose
        ) {
            MapPhotoPanelImage(
                root: root,
                photoId: pin.photoId,
                color: pin.color,
                accessibilityLabel: Text("Photo of \(pin.name)", bundle: .module)
            )
        }
    }
}

/// A photo or a weather the game master shows on the map, in the photo popover: the picture
/// with its name, Close and Full Screen.
struct MapPhotoPopoverContent: View {
    let item: MapPhotoPopoverItem
    let onShowFullScreen: () -> Void
    let onClose: () -> Void

    @Environment(MapRootModel.self) private var root

    /// What VoiceOver says for a weather: its name, or the word "Weather" when it has none (or
    /// the name did not arrive). See CODE_AUDIT_24 §8.3.
    static func weatherAccessibilityName(title: String?) -> String {
        guard let title, !title.isEmpty else { return String(localized: "Weather", bundle: .module) }
        return title
    }

    var body: some View {
        let name = item.title ?? (item.module == .photo
            ? root.photoRoot.itemControllable.nameSync(itemId: item.itemId)
            : "")
        MapPhotoPanel(title: name, onShowFullScreen: onShowFullScreen, onClose: onClose) {
            if item.module == .photo {
                MapPhotoPanelImage(
                    root: root,
                    photoId: item.itemId,
                    color: .accentColor,
                    accessibilityLabel: name.isEmpty
                        ? Text("Photo", bundle: .module)
                        : Text("Photo of \(name)", bundle: .module)
                )
            } else {
                root.weatherRoot.viewController.gamePopoverViewer(root: root.weatherRoot, itemId: item.itemId)
                    .accessibilityLabel(Text(verbatim: Self.weatherAccessibilityName(title: item.title)))
            }
        }
    }
}

/// A photo as the picture of a popover panel.
struct MapPhotoPanelImage: View {
    let root: MapRootModel
    let photoId: UUID?
    let color: Color
    let accessibilityLabel: Text

    @ScaledMetric(relativeTo: .body) private var photoSide = MapPinPhotoSharing.photoSide

    var body: some View {
        // `AsyncThumbnail` switches to the full-size photo cache for a presentation this
        // large. The source photo is rarely square: anchor the `.fill` overflow to the top,
        // like the pin token does, so a portrait keeps its head in view.
        root.photoRoot.viewController.mapImage(
            root: root.photoRoot,
            for: photoId,
            size: CGSize(width: photoSide, height: photoSide),
            color: color
        )
        .accessibilityLabel(accessibilityLabel)
    }
}

/// A big square picture in a popover panel. Its controls stand on the picture: Close at the
/// bottom leading corner, the name at the bottom center, Full Screen at the bottom trailing
/// corner.
struct MapPhotoPanel<Picture: View>: View {
    let title: String
    let onShowFullScreen: (() -> Void)?
    let onClose: () -> Void
    @ViewBuilder let picture: Picture

    @ScaledMetric(relativeTo: .body) private var photoSide = MapPinPhotoSharing.photoSide

    var body: some View {
        picture
            .frame(
                width: photoSide,
                height: photoSide,
                alignment: .top
            )
            .overlay(alignment: .bottom) {
                MapPhotoPanelControls(
                    title: title,
                    onShowFullScreen: onShowFullScreen,
                    onClose: onClose
                )
            }
            .clipShape(.rect(cornerRadius: MapPopoverGeometry.cornerRadius - MapPopoverLayout.contentInset))
            .padding(MapPopoverLayout.contentInset)
    }
}

/// The row on the bottom edge of the picture: Close, the name and Full Screen.
private struct MapPhotoPanelControls: View {
    let title: String
    let onShowFullScreen: (() -> Void)?
    let onClose: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: MapPhotoPanelLayout.padding) {
            MapPhotoOverlayButton(
                title: Text("Close", bundle: .module),
                systemImage: "xmark",
                action: onClose
            )
            Spacer(minLength: 0)
            if !title.isEmpty {
                Text(verbatim: title)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal)
                    .padding(.vertical, MapPhotoPanelLayout.padding)
                    .modifier(MapPhotoGlass(shape: .capsule))
                    .accessibilityHidden(true)
            }
            Spacer(minLength: 0)
            if let onShowFullScreen {
                MapPhotoOverlayButton(
                    title: Text("Full Screen", bundle: .module),
                    systemImage: "arrow.up.left.and.arrow.down.right",
                    action: onShowFullScreen
                )
            } else {
                // Keeps the name centered on the picture.
                MapPhotoOverlayButton.placeholder
            }
        }
        .padding(MapPhotoPanelLayout.padding)
    }
}

enum MapPhotoPanelLayout {
    /// The space between the picture's edge and its controls.
    static let padding: CGFloat = 8
}

/// A round button on the picture: Liquid Glass, a material on visionOS, where Liquid Glass is
/// unavailable.
private struct MapPhotoOverlayButton: View {
    let title: Text
    let systemImage: String
    let action: () -> Void

    @ScaledMetric(relativeTo: .body) private var diameter = MapPhotoOverlayButton.baseDiameter

#if os(macOS)
    static let baseDiameter: CGFloat = 32
#else
    static let baseDiameter: CGFloat = 44
#endif

    /// An invisible button-sized spacer.
    static var placeholder: some View {
        MapPhotoOverlayButtonPlaceholder()
    }

    var body: some View {
        Button(action: action) {
            Label {
                title
            } icon: {
                Image(systemName: systemImage)
            }
            .labelStyle(.iconOnly)
#if os(tvOS) || os(visionOS)
            .padding(MapPhotoPanelLayout.padding)
#else
            .frame(width: diameter, height: diameter)
#endif
            .contentShape(.circle)
        }
        .modifier(MapPhotoOverlayButtonStyle())
        .help(title)
    }
}

private struct MapPhotoOverlayButtonPlaceholder: View {
    @ScaledMetric(relativeTo: .body) private var diameter = MapPhotoOverlayButton.baseDiameter

    var body: some View {
        Color.clear
            .frame(width: diameter, height: diameter)
            .accessibilityHidden(true)
    }
}

/// tvOS uses the glass button style, whose focus effect the remote needs; visionOS the bordered
/// style; iOS and macOS a plain button on Liquid Glass. A glass button style next to the map's
/// drag gestures made AppKit stop delivering clicks (see `BattleRoundHeaderActions`).
private struct MapPhotoOverlayButtonStyle: ViewModifier {
    func body(content: Content) -> some View {
#if os(tvOS)
        content
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
#elseif os(visionOS)
        content
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
#elseif os(iOS)
        content
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
#else
        content
            .buttonStyle(.plain)
            .glassEffect(.regular, in: .circle)
#endif
    }
}

/// Liquid Glass behind a control on the picture, a material on visionOS.
private struct MapPhotoGlass<S: Shape>: ViewModifier {
    let shape: S

    func body(content: Content) -> some View {
#if os(visionOS)
        content.background(.regularMaterial, in: shape)
#else
        content.glassEffect(.regular, in: shape)
#endif
    }
}

#Preview("Pin Photo Popover", traits: .mockData) {
    MapPinPhotoPopoverContent(pin: .empty(MapModel.previewId), onShowFullScreen: {}, onClose: {})
        .background(.regularMaterial, in: .rect(cornerRadius: MapPopoverGeometry.cornerRadius))
        .padding()
        .background(Color.blue.gradient)
        .environment(MapRootModel.preview)
}

#Preview("Map Photo Popover", traits: .mockData) {
    MapPhotoPopoverContent(
        item: MapPhotoPopoverItem(itemId: UUID(), mapId: UUID(), anchor: .zero, title: "Throne Room"),
        onShowFullScreen: {},
        onClose: {}
    )
        .background(.regularMaterial, in: .rect(cornerRadius: MapPopoverGeometry.cornerRadius))
        .padding()
        .background(Color.blue.gradient)
        .environment(MapRootModel.preview)
}
