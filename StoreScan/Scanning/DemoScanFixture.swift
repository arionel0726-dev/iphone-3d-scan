import Foundation

#if DEBUG
/// Debug-only demo scan, excluded from Release builds entirely by the
/// `#if DEBUG` guard around this whole file. It exists so the real upload
/// path — auth, POST /api/scans, server-side Zod validation — can be
/// exercised on hardware with no LiDAR sensor (or in the Simulator, where
/// `RoomCaptureSession.isSupported` is false), without ever touching the
/// real RoomPlan capture flow in ScanCaptureCoordinator /
/// CapturedRoomDTOMapper.
///
/// The payload is a fixed, known small rectangular room (4m x 3m, one door,
/// one window, one object) built directly as a `ScanUploadDTO`, strictly
/// matching back/src/scan-dto.ts's `scanUploadDtoSchema`. It is never routed
/// through RoomPlan or through CapturedRoomDTOMapper.
///
/// It is explicitly marked as non-real data using only fields the contract
/// already allows free text in (`device.model`, `device.roomPlanVersion`),
/// not an invented DTO field — the contract itself is never changed for
/// this.
enum DemoScanFixture {
    static func makeUploadDTO(scanId: UUID, storeId: UUID, targetLayoutId: UUID?) -> ScanUploadDTO {
        let identity: ScanTransformDTO = [
            1, 0, 0, 0,
            0, 1, 0, 0,
            0, 0, 1, 0,
            0, 0, 0, 1,
        ]

        // 90° rotation about Y (ARKit's up axis), column-major, matching the
        // flattening CapturedRoomDTOMapper uses for a real transform.
        func translated(_ transform: ScanTransformDTO, x: Double, y: Double, z: Double) -> ScanTransformDTO {
            var t = transform
            t[12] = x
            t[13] = y
            t[14] = z
            return t
        }
        let rotateY90: ScanTransformDTO = [
            0, 0, -1, 0,
            0, 1, 0, 0,
            1, 0, 0, 0,
            0, 0, 0, 1,
        ]

        let wallHeight = 2.7
        let wallThickness = 0.1

        let floor = ScanSurfaceDTO(
            sourceId: "demo-floor-1",
            kind: .floor,
            confidence: .high,
            transform: identity,
            dimensions: ScanDimensionsDTO(width: 4, height: 0, length: 3),
            polygonCorners: [
                ScanPointDTO(x: 0, y: 0, z: 0),
                ScanPointDTO(x: 4, y: 0, z: 0),
                ScanPointDTO(x: 4, y: 0, z: 3),
                ScanPointDTO(x: 0, y: 0, z: 3),
            ]
        )

        let southWall = ScanSurfaceDTO(
            sourceId: "demo-wall-south",
            kind: .wall,
            confidence: .high,
            transform: translated(identity, x: 2, y: wallHeight / 2, z: 0),
            dimensions: ScanDimensionsDTO(width: 4, height: wallHeight, length: wallThickness),
            polygonCorners: nil
        )
        let northWall = ScanSurfaceDTO(
            sourceId: "demo-wall-north",
            kind: .wall,
            confidence: .high,
            transform: translated(identity, x: 2, y: wallHeight / 2, z: 3),
            dimensions: ScanDimensionsDTO(width: 4, height: wallHeight, length: wallThickness),
            polygonCorners: nil
        )
        let westWall = ScanSurfaceDTO(
            sourceId: "demo-wall-west",
            kind: .wall,
            confidence: .high,
            transform: translated(rotateY90, x: 0, y: wallHeight / 2, z: 1.5),
            dimensions: ScanDimensionsDTO(width: 3, height: wallHeight, length: wallThickness),
            polygonCorners: nil
        )
        let eastWall = ScanSurfaceDTO(
            sourceId: "demo-wall-east",
            kind: .wall,
            confidence: .high,
            transform: translated(rotateY90, x: 4, y: wallHeight / 2, z: 1.5),
            dimensions: ScanDimensionsDTO(width: 3, height: wallHeight, length: wallThickness),
            polygonCorners: nil
        )
        let door = ScanSurfaceDTO(
            sourceId: "demo-door-1",
            kind: .door,
            confidence: .medium,
            transform: translated(identity, x: 1, y: 1.05, z: 0),
            dimensions: ScanDimensionsDTO(width: 0.9, height: 2.1, length: wallThickness),
            polygonCorners: nil
        )
        let window = ScanSurfaceDTO(
            sourceId: "demo-window-1",
            kind: .window,
            confidence: .medium,
            transform: translated(rotateY90, x: 4, y: 1.5, z: 2.2),
            dimensions: ScanDimensionsDTO(width: 1.2, height: 1.2, length: wallThickness),
            polygonCorners: nil
        )

        let table = ScanObjectDTO(
            sourceId: "demo-object-1",
            category: .table,
            confidence: .medium,
            transform: translated(identity, x: 2, y: 0.4, z: 1.5),
            dimensions: ScanDimensionsDTO(width: 1.2, height: 0.8, length: 0.75)
        )

        let isoFormatter: ISO8601DateFormatter = {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            return formatter
        }()

        return ScanUploadDTO(
            scanId: scanId,
            capturedAt: isoFormatter.string(from: Date()),
            device: ScanDeviceDTO(
                model: "Demo Fixture (без LiDAR)",
                osVersion: DeviceInfo.osVersion,
                roomPlanVersion: "demo-fixture-v1"
            ),
            storeId: storeId,
            targetLayoutId: targetLayoutId,
            surfaces: [floor, southWall, northWall, westWall, eastWall, door, window],
            objects: [table]
        )
    }
}
#endif
