import SwiftUI

/// Embeds RoomPlan's RoomCaptureViewController (the camera feed, AR overlays
/// and built-in scanning guidance) in SwiftUI. A view CONTROLLER wrapper
/// (not UIViewRepresentable) because the delegate conformances that make
/// RoomPlan work live on that controller — see RoomCaptureViewController.swift
/// for why. All scan lifecycle control (start/finish/cancel) happens through
/// ScanCaptureCoordinator, which owns the controller — this wrapper just
/// displays it.
struct RoomCaptureRepresentable: UIViewControllerRepresentable {
    let coordinator: ScanCaptureCoordinator

    func makeUIViewController(context: Context) -> RoomCaptureViewController {
        coordinator.viewController
    }

    func updateUIViewController(_ uiViewController: RoomCaptureViewController, context: Context) {}
}
