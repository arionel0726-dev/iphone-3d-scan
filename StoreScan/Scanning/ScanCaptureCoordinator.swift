import Combine
import Foundation
import RoomPlan

/// What the scan screen shows. RoomPlan's own CaptureError (deviceNotSupported,
/// worldTrackingFailure, exceedSceneSizeLimit, deviceTooHot,
/// invalidARConfiguration, internalError) does NOT include a camera-permission
/// case — Apple's RoomCaptureSession assumes the camera is already available,
/// so this app checks AVFoundation's camera authorization itself, before
/// ever starting a session (see CameraPermission.swift).
enum ScanCaptureState: Equatable {
    case idle
    case scanning
    /// The user tapped "Завершить" and RoomPlan is still merging/processing
    /// the final result.
    case processing
    case finished(roomSummary: String)
    case cancelled
    case failed(String)
}

/// Bridges RoomPlan's results into SwiftUI state for the scan screen. The
/// actual RoomCaptureView/RoomCaptureViewDelegate/RoomCaptureSessionDelegate
/// plumbing lives in RoomCaptureViewController (a UIViewController, which is
/// why: RoomCaptureViewDelegate inherits NSCoding, and only a Cocoa class
/// that genuinely supports it — not a plain NSObject — satisfies that for
/// free). This type stays a plain ObservableObject and talks to the view
/// controller only through its small `run()`/`stop()` surface plus the two
/// result callbacks below.
@MainActor
final class ScanCaptureCoordinator: ObservableObject {
    @Published private(set) var state: ScanCaptureState = .idle
    private(set) var capturedRoom: CapturedRoom?

    let viewController = RoomCaptureViewController()

    private var wasCancelled = false

    init() {
        viewController.resultHandler = self
    }

    func start() {
        guard RoomCaptureSession.isSupported else {
            state = .failed("Это устройство не поддерживает сканирование RoomPlan (нужен iPhone/iPad с LiDAR).")
            return
        }

        capturedRoom = nil
        state = .scanning
        viewController.run()
    }

    /// "Завершить": stop and keep whatever RoomPlan finishes processing.
    func finish() {
        guard state == .scanning else { return }
        state = .processing
        viewController.stop()
    }

    /// "Отмена": stop and discard the result once it arrives.
    func cancel() {
        guard state == .scanning || state == .processing else { return }
        wasCancelled = true
        state = .processing
        viewController.stop()
    }

    func reset() {
        capturedRoom = nil
        wasCancelled = false
        state = .idle
    }

    func handleCaptureResult(_ room: CapturedRoom, error: Error?) {
        if let error {
            state = .failed(describeCaptureError(error))
            return
        }

        if wasCancelled {
            state = .cancelled
            return
        }

        capturedRoom = room
        state = .finished(roomSummary: "Стен: \(room.walls.count) · объектов: \(room.objects.count)")
    }

    func handleSessionError(_ error: Error) {
        state = .failed(describeCaptureError(error))
    }
}

private func describeCaptureError(_ error: Error) -> String {
    guard let captureError = error as? RoomCaptureSession.CaptureError else {
        return error.localizedDescription
    }

    switch captureError {
    case .deviceNotSupported:
        return "Это устройство не поддерживает сканирование RoomPlan."
    case .deviceTooHot:
        return "Устройство перегрелось. Дайте ему остыть и повторите сканирование."
    case .exceedSceneSizeLimit:
        return "Помещение слишком большое для одного скана. Разбейте его на части."
    case .invalidARConfiguration:
        return "Не удалось запустить AR-сессию на этом устройстве."
    case .worldTrackingFailure:
        return "Потеряно отслеживание положения устройства. Переместитесь в более освещённое место и попробуйте снова."
    case .internalError:
        return "Внутренняя ошибка сканирования. Попробуйте ещё раз."
    @unknown default:
        return captureError.localizedDescription
    }
}
