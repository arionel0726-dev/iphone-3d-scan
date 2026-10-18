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

/// Bridges RoomPlan's UIKit delegate callbacks into SwiftUI state. Owns the
/// one RoomCaptureView/RoomCaptureSession for the lifetime of a single scan
/// screen.
@MainActor
final class ScanCaptureCoordinator: NSObject, ObservableObject {
    @Published private(set) var state: ScanCaptureState = .idle
    private(set) var capturedRoom: CapturedRoom?

    let captureView: RoomCaptureView

    override init() {
        captureView = RoomCaptureView(frame: .zero)
        super.init()
        captureView.delegate = self
        captureView.captureSession.delegate = self
    }

    func start() {
        guard RoomCaptureSession.isSupported else {
            state = .failed("Это устройство не поддерживает сканирование RoomPlan (нужен iPhone/iPad с LiDAR).")
            return
        }

        capturedRoom = nil
        state = .scanning
        captureView.captureSession.run(configuration: RoomCaptureSession.Configuration())
    }

    /// "Завершить": stop and keep whatever RoomPlan finishes processing.
    func finish() {
        guard state == .scanning else { return }
        state = .processing
        captureView.captureSession.stop()
    }

    /// "Отмена": stop and discard the result once it arrives.
    func cancel() {
        guard state == .scanning || state == .processing else { return }
        wasCancelled = true
        state = .processing
        captureView.captureSession.stop()
    }

    func reset() {
        capturedRoom = nil
        wasCancelled = false
        state = .idle
    }

    private var wasCancelled = false
}

extension ScanCaptureCoordinator: RoomCaptureViewDelegate {
    nonisolated func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: Error?) -> Bool {
        true
    }

    nonisolated func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
        Task { @MainActor in
            if let error {
                state = .failed(describeCaptureError(error))
                return
            }

            if wasCancelled {
                state = .cancelled
                return
            }

            capturedRoom = processedResult
            let wallCount = processedResult.walls.count
            let objectCount = processedResult.objects.count
            state = .finished(roomSummary: "Стен: \(wallCount) · объектов: \(objectCount)")
        }
    }
}

extension ScanCaptureCoordinator: RoomCaptureSessionDelegate {
    nonisolated func captureSession(_ session: RoomCaptureSession, didEndWith data: CapturedRoomData, error: Error?) {
        guard let error else { return }
        Task { @MainActor in
            state = .failed(describeCaptureError(error))
        }
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
