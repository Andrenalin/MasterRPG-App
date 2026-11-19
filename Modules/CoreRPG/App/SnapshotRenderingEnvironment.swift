// @copyright André Trettin

import SwiftUI

public extension EnvironmentValues {
    /// True only while a view is rendered for a snapshot test; the snapshot test environment sets it.
    ///
    /// A snapshot is hosted without a window scene and is taken the moment the view is laid out, so
    /// what needs a scene or runs in the background is skipped when this is set:
    /// - `@SceneStorage` based state restoration, which logs "Accessing a SceneStorage value outside
    ///   of being installed on a View" and only ever yields its default value without a scene;
    /// - loading a 3D model into a `RealityView`, which a snapshot cannot show anyway (it shows the
    ///   progress view) and whose RealityIO live scene update can still be running when the test
    ///   process exits, which crashes the process on a background thread.
    @Entry var isSnapshotRendering: Bool = false
}
