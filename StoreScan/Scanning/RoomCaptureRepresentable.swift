import RoomPlan
import SwiftUI

/// Embeds RoomPlan's UIKit `RoomCaptureView` (the camera feed, AR overlays
/// and built-in scanning guidance) in SwiftUI. All scan lifecycle control
/// (start/finish/cancel) happens through ScanCaptureCoordinator, which owns
/// the view — this wrapper just displays it.
struct RoomCaptureRepresentable: UIViewRepresentable {
    let coordinator: ScanCaptureCoordinator

    func makeUIView(context: Context) -> RoomCaptureView {
        coordinator.captureView
    }

    func updateUIView(_ uiView: RoomCaptureView, context: Context) {}
}
