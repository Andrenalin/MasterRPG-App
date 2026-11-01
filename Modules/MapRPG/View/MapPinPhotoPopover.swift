// @copyright André Trettin

import CoreRPG
import PhotoRPG
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

    /// Edge length of the photo, large enough to recognize a face across the table.
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

/// The popover's content: the pin's photo and its name.
struct MapPinPhotoPopoverContent: View {
    let pin: MapPinModel

    @Environment(MapRootModel.self) private var root

    var body: some View {
        VStack(spacing: MapPopoverLayout.contentInset) {
            // `AsyncThumbnail` switches to the full-size photo cache for a presentation this
            // large. The source photo is rarely square: anchor the `.fill` overflow to the top,
            // like the pin token does, so a portrait keeps its head in view.
            root.photoRoot.viewController.mapImage(
                root: root.photoRoot,
                for: pin.photoId,
                size: CGSize(width: MapPinPhotoSharing.photoSide, height: MapPinPhotoSharing.photoSide),
                color: pin.color
            )
            .frame(
                width: MapPinPhotoSharing.photoSide,
                height: MapPinPhotoSharing.photoSide,
                alignment: .top
            )
            .clipShape(.rect(cornerRadius: MapPopoverGeometry.cornerRadius - MapPopoverLayout.contentInset))
            .accessibilityLabel(Text("Photo of \(pin.name)", bundle: .module))

            if !pin.name.isEmpty {
                Text(verbatim: pin.name)
                    .font(.headline)
                    .lineLimit(1)
                    .padding(.bottom, MapPopoverLayout.contentInset / 2)
            }
        }
        .padding(MapPopoverLayout.contentInset)
        .frame(maxWidth: MapPinPhotoSharing.photoSide + MapPopoverLayout.contentInset * 2)
    }
}

#Preview("Pin Photo Popover", traits: .mockData) {
    MapPinPhotoPopoverContent(pin: .empty(MapModel.previewId))
        .background(.regularMaterial, in: .rect(cornerRadius: MapPopoverGeometry.cornerRadius))
        .padding()
        .background(Color.blue.gradient)
        .environment(MapRootModel.preview)
}
