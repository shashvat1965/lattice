import AppKit
import SwiftUI
import LatticeKit

/// The Layouts row in the main window. The page itself lives in `UI/Layouts`;
/// this wrapper keeps the window shell and the snapshot harness pointed at the same tree.
struct LayoutsGallery: View {

    @ObservedObject var model: AppModel

    var body: some View {
        LayoutsPage(model: model)
    }
}
