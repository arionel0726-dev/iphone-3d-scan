import RoomPlan
import UIKit

/// Hosts RoomPlan's `RoomCaptureView` and implements its two delegate
/// protocols.
///
/// Why this has to be a UIViewController (and not a plain `NSObject`):
/// Apple declares `RoomCaptureViewDelegate` as inheriting from `NSCoding`
/// (`protocol RoomCaptureViewDelegate : NSCoding`, see
/// developer.apple.com/documentation/roomplan/roomcaptureviewdelegate).
/// Conforming to it therefore requires `init?(coder:)` and
/// `encode(with:)`. A bare `NSObject` subclass does not get those for
/// free — only Cocoa classes that actually support nib/storyboard
/// archiving do, `UIViewController` (via `UIResponder`) among them. That is
/// the real reason this type is a UIViewController rather than a stubbed-out
/// NSCoding conformance bolted onto an NSObject coordinator: it already,
/// legitimately, has what the protocol asks for.
///
/// This controller owns only the RoomPlan view/session lifecycle. The
/// SwiftUI-facing state (@Published state for the Начать/Завершить/Отмена
/// screen) lives in ScanCaptureCoordinator, which this controller reports
/// results to via `resultHandler` — kept as a separate, plain
/// `ObservableObject` so it is not itself forced into the same NSCoding
/// requirement.
final class RoomCaptureViewController: UIViewController {
    private(set) lazy var captureView = RoomCaptureView(frame: .zero)
    weak var resultHandler: ScanCaptureCoordinator?

    override func viewDidLoad() {
        super.viewDidLoad()
        captureView.delegate = self
        captureView.captureSession.delegate = self
        captureView.frame = view.bounds
        captureView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(captureView)
    }

    func run() {
        captureView.captureSession.run(configuration: RoomCaptureSession.Configuration())
    }

    func stop() {
        captureView.captureSession.stop()
    }
}

extension RoomCaptureViewController: RoomCaptureViewDelegate {
    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: Error?) -> Bool {
        true
    }

    func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
        resultHandler?.handleCaptureResult(processedResult, error: error)
    }
}

extension RoomCaptureViewController: RoomCaptureSessionDelegate {
    func captureSession(_ session: RoomCaptureSession, didEndWith data: CapturedRoomData, error: Error?) {
        guard let error else { return }
        resultHandler?.handleSessionError(error)
    }
}
