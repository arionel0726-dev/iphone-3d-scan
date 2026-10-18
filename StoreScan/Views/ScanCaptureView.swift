import RoomPlan
import SwiftUI
import UIKit

/// One-room RoomPlan capture: Начать / Завершить / Отмена, then an
/// automatic upload of the resulting DTO. No USDZ export, no multi-room
/// stitching, no photo capture — matches the MVP scope.
struct ScanCaptureView: View {
    @EnvironmentObject private var appState: AppState
    let store: Store
    let targetLayout: LayoutSummary?

    @StateObject private var coordinator = ScanCaptureCoordinator()
    @State private var cameraStatus = CameraPermission.currentStatus
    @State private var uploadState: UploadState = .notStarted
    @State private var scanId = UUID()
    /// Set only by the Debug-only demo-scan button; never true in a Release
    /// build, and never set anywhere in the real RoomPlan capture path.
    @State private var isDemoUpload = false

    private enum UploadState: Equatable {
        case notStarted
        case uploading
        case succeeded(UUID)
        case failed(String)
    }

    var body: some View {
        ZStack {
            if RoomCaptureSession.isSupported && !isDemoUpload {
                RoomCaptureRepresentable(coordinator: coordinator)
                    .ignoresSafeArea()
            } else {
                Color(.systemBackground).ignoresSafeArea()
            }

            VStack {
                Spacer()
                overlay
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .padding()
            }
        }
        .navigationTitle(store.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Закрыть") { appState.cancelScan() }
            }
        }
        .onChange(of: coordinator.state) { _, newState in
            if newState == .cancelled {
                appState.cancelScan()
            }
            if case .finished = newState, uploadState == .notStarted {
                Task { await upload() }
            }
        }
    }

    @ViewBuilder
    private var overlay: some View {
        if isDemoUpload {
            demoOverlay
        } else if !RoomCaptureSession.isSupported {
            VStack(spacing: 12) {
                StatusBlock(
                    icon: "exclamationmark.triangle.fill",
                    title: "Устройство не поддерживается",
                    message: "Для сканирования нужен iPhone или iPad с датчиком LiDAR и RoomPlan (iOS 16+).",
                    action: ("Назад", { appState.cancelScan() })
                )
                #if DEBUG
                demoScanButton
                #endif
            }
        } else if cameraStatus == .denied {
            StatusBlock(
                icon: "camera.fill",
                title: "Нет доступа к камере",
                message: "Разрешите доступ к камере в Настройках, чтобы начать сканирование.",
                action: ("Открыть настройки", openSettings)
            )
        } else {
            switch coordinator.state {
            case .idle:
                VStack(spacing: 12) {
                    StatusBlock(
                        icon: "viewfinder",
                        title: "Готово к сканированию",
                        message: targetLayout.map { "Скан будет добавлен к планировке «\($0.name)»." }
                            ?? "Для скана будет создана новая планировка.",
                        primaryAction: ("Начать", startTapped)
                    )
                    #if DEBUG
                    demoScanButton
                    #endif
                }
            case .scanning:
                HStack(spacing: 16) {
                    Button("Отмена", role: .cancel) { coordinator.cancel() }
                        .buttonStyle(.bordered)
                    Button("Завершить") { coordinator.finish() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                }
            case .processing:
                StatusBlock(icon: "hourglass", title: "Обработка скана…", message: "Это займёт несколько секунд.")
            case let .finished(summary):
                uploadStatusBlock(summary: summary)
            case .cancelled:
                StatusBlock(icon: "xmark.circle", title: "Сканирование отменено", message: "")
            case let .failed(message):
                StatusBlock(
                    icon: "exclamationmark.triangle.fill",
                    title: "Не удалось выполнить сканирование",
                    message: message,
                    action: ("Назад", { appState.cancelScan() })
                )
            }
        }
    }

    #if DEBUG
    /// Debug-only: sends a fixed test DTO through the real upload path
    /// (auth + POST /api/scans) instead of running RoomPlan, so the API
    /// integration can be checked on hardware with no LiDAR sensor. Never
    /// compiled into a Release build, and never touches
    /// ScanCaptureCoordinator / CapturedRoomDTOMapper.
    @ViewBuilder
    private var demoScanButton: some View {
        VStack(spacing: 4) {
            Button {
                isDemoUpload = true
                Task { await startDemoUpload() }
            } label: {
                Label("Демо-скан (тестовые данные)", systemImage: "wand.and.stars")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.orange)

            Text("Отладочный режим: отправляет фиксированные тестовые данные вместо реального сканирования помещения.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder
    private var demoOverlay: some View {
        switch uploadState {
        case .notStarted, .uploading:
            StatusBlock(
                icon: "wand.and.stars",
                title: "Отправка демо-скана…",
                message: "Это тестовые данные, а не результат реального сканирования помещения.",
                isLoading: true
            )
        case let .failed(message):
            StatusBlock(
                icon: "wifi.exclamationmark",
                title: "Не удалось отправить демо-скан",
                message: message,
                primaryAction: ("Повторить", { Task { await startDemoUpload() } }),
                action: ("Отмена", { appState.cancelScan() })
            )
        case .succeeded:
            StatusBlock(
                icon: "checkmark.circle.fill",
                title: "Демо-скан отправлен",
                message: "Это тестовые данные, отправленные через настоящий API, а не реальный скан помещения."
            )
        }
    }
    #endif

    @ViewBuilder
    private func uploadStatusBlock(summary: String) -> some View {
        switch uploadState {
        case .notStarted, .uploading:
            StatusBlock(icon: "arrow.up.circle", title: "Отправка скана…", message: summary, isLoading: true)
        case let .failed(message):
            StatusBlock(
                icon: "wifi.exclamationmark",
                title: "Не удалось отправить скан",
                message: message,
                primaryAction: ("Повторить", { Task { await upload() } }),
                action: ("Отмена", { appState.cancelScan() })
            )
        case .succeeded:
            StatusBlock(icon: "checkmark.circle.fill", title: "Скан отправлен", message: summary)
        }
    }

    private func startTapped() {
        Task {
            let granted = await CameraPermission.requestIfNeeded()
            cameraStatus = CameraPermission.currentStatus
            if granted {
                coordinator.start()
            }
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func upload() async {
        guard let room = coordinator.capturedRoom else { return }
        let dto = CapturedRoomDTOMapper.makeUploadDTO(
            from: room,
            scanId: scanId,
            capturedAt: Date(),
            storeId: store.id,
            targetLayoutId: targetLayout?.id
        )
        await performUpload(dto, isDemo: false)
    }

    #if DEBUG
    private func startDemoUpload() async {
        let dto = DemoScanFixture.makeUploadDTO(
            scanId: scanId,
            storeId: store.id,
            targetLayoutId: targetLayout?.id
        )
        await performUpload(dto, isDemo: true)
    }
    #endif

    private func performUpload(_ dto: ScanUploadDTO, isDemo: Bool) async {
        uploadState = .uploading
        do {
            let scan = try await appState.apiClient.uploadScan(dto)
            uploadState = .succeeded(scan.id)
            appState.finishScan(outcome: .success(scanId: scan.id, reviewURLBase: appState.reviewURLBase, isDemo: isDemo))
        } catch APIError.sessionExpired {
            appState.handleSessionExpired()
        } catch {
            uploadState = .failed(error.localizedDescription)
        }
    }
}

private struct StatusBlock: View {
    let icon: String
    let title: String
    var message: String = ""
    var isLoading = false
    var primaryAction: (String, () -> Void)?
    var action: (String, () -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            if isLoading {
                ProgressView()
            } else {
                Image(systemName: icon).font(.system(size: 32))
            }
            Text(title).font(.headline)
            if !message.isEmpty {
                Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            if let primaryAction {
                Button(primaryAction.0, action: primaryAction.1)
                    .buttonStyle(.borderedProminent)
            }
            if let action {
                Button(action.0, action: action.1)
                    .buttonStyle(.bordered)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
    }
}
