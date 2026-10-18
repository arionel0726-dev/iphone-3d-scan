import Foundation

// Versioned wire contract for a single RoomPlan capture, mirroring
// back/src/scan-dto.ts in the 2-3d-store repository EXACTLY — field names,
// nesting and the enum vocabularies below must match that file byte for
// byte. If scan-dto.ts changes, this file (and ScanUploadDTOCodingTests)
// must change with it; do not improvise new fields or rename anything here
// on the iOS side alone.
//
// This file is intentionally pure Foundation (no RoomPlan/ARKit/UIKit
// imports) so the wire format can be reasoned about and unit-tested in
// isolation from the capture UI — see CapturedRoomDTOMapper.swift for the
// (transform-free) code that fills these structs from a RoomPlan
// `CapturedRoom`.
//
// Units are meters/radians, exactly as ARKit/RoomPlan reports them. No
// coordinate conversion happens on the device — see scan-normalize.ts on
// the backend for where meters become layout centimeters.

/// The exact DTO version this build speaks. Must match
/// `SCAN_DTO_VERSION` in back/src/scan-dto.ts.
let scanDTOVersion = 1

enum ScanConfidenceDTO: String, Codable, Equatable {
    case low, medium, high
}

/// A flat 16-number, COLUMN-MAJOR encoding of a 4x4 transform:
/// [col0.x, col0.y, col0.z, col0.w, col1.x, ..., col3.w], where column 3 is
/// translation (tx, ty, tz, 1). This is a contract the backend defines
/// (back/src/scan-dto.ts), not something inferred from simd_float4x4's
/// default Codable behavior — see CapturedRoomDTOMapper.swift for the
/// explicit column flattening that produces this.
typealias ScanTransformDTO = [Double]

struct ScanDimensionsDTO: Codable, Equatable {
    var width: Double
    var height: Double
    var length: Double
}

struct ScanPointDTO: Codable, Equatable {
    var x: Double
    var y: Double
    var z: Double
}

enum ScanSurfaceKindDTO: String, Codable, Equatable {
    case floor, wall, door, window, opening
}

struct ScanSurfaceDTO: Equatable {
    var sourceId: String
    var kind: ScanSurfaceKindDTO
    var confidence: ScanConfidenceDTO
    var transform: ScanTransformDTO
    var dimensions: ScanDimensionsDTO
    /// nil means "no usable polygon" (RoomPlan gave fewer than 3 corners,
    /// or none at all). The backend's Zod schema uses `.nullable()`
    /// (not `.optional()`) for this field: a JSON `null` is required when
    /// absent, a MISSING key is not accepted. Swift's default
    /// Codable synthesis would instead *omit* the key for a nil Optional
    /// (via encodeIfPresent), which would fail backend validation — so
    /// this type encodes/decodes the key explicitly below rather than
    /// relying on the compiler-synthesized conformance.
    var polygonCorners: [ScanPointDTO]?
}

extension ScanSurfaceDTO: Codable {
    enum CodingKeys: String, CodingKey {
        case sourceId, kind, confidence, transform, dimensions, polygonCorners
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sourceId = try container.decode(String.self, forKey: .sourceId)
        kind = try container.decode(ScanSurfaceKindDTO.self, forKey: .kind)
        confidence = try container.decode(ScanConfidenceDTO.self, forKey: .confidence)
        transform = try container.decode(ScanTransformDTO.self, forKey: .transform)
        dimensions = try container.decode(ScanDimensionsDTO.self, forKey: .dimensions)
        polygonCorners = try container.decode([ScanPointDTO]?.self, forKey: .polygonCorners)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sourceId, forKey: .sourceId)
        try container.encode(kind, forKey: .kind)
        try container.encode(confidence, forKey: .confidence)
        try container.encode(transform, forKey: .transform)
        try container.encode(dimensions, forKey: .dimensions)
        // Plain `encode(_:forKey:)` on an Optional value encodes JSON `null`
        // for `nil` (unlike `encodeIfPresent`, which would drop the key).
        try container.encode(polygonCorners, forKey: .polygonCorners)
    }
}

/// RoomPlan's `CapturedRoom.Object.Category` vocabulary (storage, table,
/// sofa, ...), plus `.unknown` for any case this build doesn't recognize —
/// RoomPlan's enum is not `@frozen`, so a future OS can add cases an older
/// build has never heard of. This is intentionally raw RoomPlan vocabulary:
/// it is never treated as a store fixture category (shelving, checkout,
/// display) anywhere in this app or in the backend.
enum ScanObjectCategoryDTO: String, Codable, Equatable {
    case storage, refrigerator, stove, bed, sink, washerDryer, toilet, bathtub
    case oven, dishwasher, table, sofa, chair, fireplace, television, stairs
    case unknown
}

struct ScanObjectDTO: Codable, Equatable {
    var sourceId: String
    var category: ScanObjectCategoryDTO
    var confidence: ScanConfidenceDTO
    var transform: ScanTransformDTO
    var dimensions: ScanDimensionsDTO
}

struct ScanDeviceDTO: Codable, Equatable {
    var model: String
    var osVersion: String?
    var roomPlanVersion: String?
}

struct ScanUploadDTO: Codable, Equatable {
    var dtoVersion: Int
    var scanId: UUID
    /// ISO 8601 / RFC 3339 UTC, e.g. "2026-10-18T19:12:52Z" — matches the
    /// backend's `z.string().datetime()` (UTC "Z" suffix, fractional
    /// seconds optional, no non-"Z" offsets accepted).
    var capturedAt: String
    var device: ScanDeviceDTO
    var storeId: UUID
    var targetLayoutId: UUID?
    var units: String
    var surfaces: [ScanSurfaceDTO]
    var objects: [ScanObjectDTO]

    init(
        scanId: UUID,
        capturedAt: String,
        device: ScanDeviceDTO,
        storeId: UUID,
        targetLayoutId: UUID?,
        surfaces: [ScanSurfaceDTO],
        objects: [ScanObjectDTO]
    ) {
        self.dtoVersion = scanDTOVersion
        self.scanId = scanId
        self.capturedAt = capturedAt
        self.device = device
        self.storeId = storeId
        self.targetLayoutId = targetLayoutId
        self.units = "meters"
        self.surfaces = surfaces
        self.objects = objects
    }
}

enum ScanDTOEncoding {
    /// Shared encoder for every request body in the app: stable key order
    /// isn't required by the backend, but matching the backend's own ISO
    /// date handling (UTC, "Z") is — dates here are always pre-formatted
    /// strings (see ScanUploadDTO.capturedAt), so no custom date strategy
    /// is needed.
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .useDefaultKeys
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        return decoder
    }
}
