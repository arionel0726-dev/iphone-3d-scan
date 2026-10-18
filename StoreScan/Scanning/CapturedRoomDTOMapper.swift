import Foundation
import RoomPlan
import simd

// Builds a ScanUploadDTO from a finished RoomPlan CapturedRoom. This file
// does NO coordinate-system math: it only flattens/renames fields into the
// wire shape back/src/scan-dto.ts expects. ARKit's meters, matrices and
// confidence levels are copied through as-is; every conversion to layout
// centimeters/degrees happens once, server-side, in scan-normalize.ts.
enum CapturedRoomDTOMapper {
    static func makeUploadDTO(
        from room: CapturedRoom,
        scanId: UUID,
        capturedAt: Date,
        storeId: UUID,
        targetLayoutId: UUID?
    ) -> ScanUploadDTO {
        var surfaces: [ScanSurfaceDTO] = []
        surfaces.append(contentsOf: room.floors.map { surfaceDTO(from: $0, kind: .floor) })
        surfaces.append(contentsOf: room.walls.map { surfaceDTO(from: $0, kind: .wall) })
        surfaces.append(contentsOf: room.doors.map { surfaceDTO(from: $0, kind: .door) })
        surfaces.append(contentsOf: room.windows.map { surfaceDTO(from: $0, kind: .window) })
        surfaces.append(contentsOf: room.openings.map { surfaceDTO(from: $0, kind: .opening) })

        let objects = room.objects.map(objectDTO(from:))

        return ScanUploadDTO(
            scanId: scanId,
            capturedAt: isoFormatter.string(from: capturedAt),
            device: deviceDTO(),
            storeId: storeId,
            targetLayoutId: targetLayoutId,
            surfaces: surfaces,
            objects: objects
        )
    }

    // MARK: - Surfaces

    private static func surfaceDTO(from surface: CapturedRoom.Surface, kind: ScanSurfaceKindDTO) -> ScanSurfaceDTO {
        ScanSurfaceDTO(
            sourceId: surface.identifier.uuidString,
            kind: kind,
            confidence: confidenceDTO(surface.confidence),
            transform: transformDTO(surface.transform),
            dimensions: dimensionsDTO(surface.dimensions),
            polygonCorners: polygonCornersDTO(surface.polygonCorners)
        )
    }

    // MARK: - Objects

    private static func objectDTO(from object: CapturedRoom.Object) -> ScanObjectDTO {
        ScanObjectDTO(
            sourceId: object.identifier.uuidString,
            category: categoryDTO(object.category),
            confidence: confidenceDTO(object.confidence),
            transform: transformDTO(object.transform),
            dimensions: dimensionsDTO(object.dimensions)
        )
    }

    private static func categoryDTO(_ category: CapturedRoom.Object.Category) -> ScanObjectCategoryDTO {
        switch category {
        case .storage: return .storage
        case .refrigerator: return .refrigerator
        case .stove: return .stove
        case .bed: return .bed
        case .sink: return .sink
        case .washerDryer: return .washerDryer
        case .toilet: return .toilet
        case .bathtub: return .bathtub
        case .oven: return .oven
        case .dishwasher: return .dishwasher
        case .table: return .table
        case .sofa: return .sofa
        case .chair: return .chair
        case .fireplace: return .fireplace
        case .television: return .television
        case .stairs: return .stairs
        @unknown default:
            // RoomPlan's enum is not frozen; a future OS can add a case
            // this build has never heard of. Never crash on it — report it
            // as "unknown" and let a manager classify the object manually
            // in the web review screen (it is already flagged needsReview
            // there for every scanned object, regardless of category).
            return .unknown
        }
    }

    // MARK: - Shared field mapping

    private static func confidenceDTO(_ confidence: CapturedRoom.Confidence) -> ScanConfidenceDTO {
        switch confidence {
        case .high: return .high
        case .medium: return .medium
        case .low: return .low
        @unknown default: return .low
        }
    }

    /// Column-major flattening of `simd_float4x4`: [col0.x...col0.w,
    /// col1.x...col1.w, col2.x...col2.w, col3.x...col3.w]. This is the
    /// backend's own defined contract (back/src/scan-dto.ts), reproduced
    /// explicitly here rather than relying on any default Codable
    /// encoding of simd_float4x4, which is not part of this contract.
    private static func transformDTO(_ matrix: simd_float4x4) -> ScanTransformDTO {
        let columns = [matrix.columns.0, matrix.columns.1, matrix.columns.2, matrix.columns.3]
        return columns.flatMap { column in
            [Double(column.x), Double(column.y), Double(column.z), Double(column.w)]
        }
    }

    /// dimensions.x -> width, dimensions.y -> height, dimensions.z -> length.
    /// This mapping is this backend's own defined contract; RoomPlan's
    /// `simd_float3` itself carries no field names.
    private static func dimensionsDTO(_ dimensions: simd_float3) -> ScanDimensionsDTO {
        ScanDimensionsDTO(
            width: Double(dimensions.x),
            height: Double(dimensions.y),
            length: Double(dimensions.z)
        )
    }

    /// nil when RoomPlan didn't produce a usable polygon (empty, or fewer
    /// than 3 points — the backend's Zod schema requires at least 3 when
    /// not null). `CapturedRoom.Surface.polygonCorners` is a plain,
    /// non-optional `[simd_float3]` in RoomPlan itself; "no polygon" shows
    /// up as an empty array there, which this maps to the DTO's explicit
    /// `null`.
    private static func polygonCornersDTO(_ corners: [simd_float3]) -> [ScanPointDTO]? {
        guard corners.count >= 3 else { return nil }
        return corners.map { ScanPointDTO(x: Double($0.x), y: Double($0.y), z: Double($0.z)) }
    }

    private static func deviceDTO() -> ScanDeviceDTO {
        ScanDeviceDTO(
            model: DeviceInfo.modelIdentifier,
            osVersion: DeviceInfo.osVersion,
            roomPlanVersion: nil
        )
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
