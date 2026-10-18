import AVFoundation

/// RoomPlan needs the camera but its own CaptureError enum has no
/// permission-denied case (deviceNotSupported/deviceTooHot/
/// exceedSceneSizeLimit/invalidARConfiguration/worldTrackingFailure/
/// internalError only) — see ScanCaptureCoordinator.swift. This app checks
/// and requests camera access itself, before ever starting a capture
/// session, so a denial surfaces as a clear message instead of an opaque
/// AR failure.
enum CameraPermission {
    enum Status {
        case authorized
        case denied
        case notDetermined
    }

    static var currentStatus: Status {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return .authorized
        case .denied, .restricted: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .denied
        }
    }

    /// Prompts the system permission dialog if not yet determined; returns
    /// whether the app can proceed.
    static func requestIfNeeded() async -> Bool {
        switch currentStatus {
        case .authorized:
            return true
        case .denied:
            return false
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        }
    }
}
