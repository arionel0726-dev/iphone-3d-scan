import XCTest
@testable import StoreScan

/// Verifies ScanUploadDTO's wire format against back/src/scan-dto.ts's Zod
/// schema, field by field. These are pure Codable tests (no RoomPlan, no
/// network) — they catch exactly the kind of mismatch that would make the
/// backend reject an otherwise-correct scan with a 400, before that is ever
/// discovered against a real device.
final class ScanUploadDTOCodingTests: XCTestCase {
    // Foundation's UUID.uuidString is always UPPERCASE; JSONEncoder's
    // built-in UUID conformance uses it as-is. Fixtures compare against
    // `.uuidString` rather than a hand-typed literal so this doesn't
    // silently depend on that casing.
    private let fixtureScanId = UUID(uuidString: "C4BCE590-7A46-418C-80DB-2ADE82DD669E")!
    private let fixtureStoreId = UUID(uuidString: "FB4E3E48-8FF5-4785-8D20-0BB82B108839")!
    private let fixtureLayoutId = UUID(uuidString: "F97E1EF9-05C7-4D18-9093-587ECCF06CCF")!

    private func makeFixtureDTO(
        polygonCorners: [ScanPointDTO]? = [
            ScanPointDTO(x: 0, y: 0, z: 0),
            ScanPointDTO(x: 4, y: 0, z: 0),
            ScanPointDTO(x: 4, y: 0, z: 3),
        ],
        osVersion: String? = "17.4",
        roomPlanVersion: String? = nil
    ) -> ScanUploadDTO {
        let surface = ScanSurfaceDTO(
            sourceId: "surface-1",
            kind: .wall,
            confidence: .high,
            transform: Array(stride(from: 0.0, to: 16.0, by: 1.0)),
            dimensions: ScanDimensionsDTO(width: 4, height: 2.7, length: 0.1),
            polygonCorners: polygonCorners
        )
        let object = ScanObjectDTO(
            sourceId: "object-1",
            category: .storage,
            confidence: .low,
            transform: Array(repeating: 0.0, count: 16),
            dimensions: ScanDimensionsDTO(width: 1, height: 1, length: 1)
        )
        return ScanUploadDTO(
            scanId: fixtureScanId,
            capturedAt: "2026-10-18T19:12:52Z",
            device: ScanDeviceDTO(model: "iPhone15,3", osVersion: osVersion, roomPlanVersion: roomPlanVersion),
            storeId: fixtureStoreId,
            targetLayoutId: fixtureLayoutId,
            surfaces: [surface],
            objects: [object]
        )
    }

    private func encodeToJSONObject(_ dto: ScanUploadDTO) throws -> [String: Any] {
        let data = try ScanDTOEncoding.makeEncoder().encode(dto)
        let object = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(object as? [String: Any])
    }

    // MARK: - Top-level shape (back/src/scan-dto.ts: scanUploadDtoSchema)

    func testTopLevelFieldsMatchBackendSchema() throws {
        let json = try encodeToJSONObject(makeFixtureDTO())

        XCTAssertEqual(json["dtoVersion"] as? Int, 1, "must equal SCAN_DTO_VERSION in scan-dto.ts")
        XCTAssertEqual(json["scanId"] as? String, fixtureScanId.uuidString)
        XCTAssertEqual(json["units"] as? String, "meters")
        XCTAssertEqual(json["storeId"] as? String, fixtureStoreId.uuidString)
        XCTAssertEqual(json["targetLayoutId"] as? String, fixtureLayoutId.uuidString)
        XCTAssertNotNil(json["capturedAt"] as? String)
        XCTAssertNotNil(json["device"] as? [String: Any])
        XCTAssertEqual((json["surfaces"] as? [Any])?.count, 1)
        XCTAssertEqual((json["objects"] as? [Any])?.count, 1)
    }

    func testCapturedAtMatchesBackendDatetimeRegex() throws {
        // Mirrors zod's `z.string().datetime()` default (no args): UTC "Z"
        // suffix required, seconds required, fractional seconds optional,
        // no other timezone offsets accepted. See back/src/scan-dto.ts.
        let pattern = #"^\d{4}-\d{2}-\d{2}T([01]\d|2[0-3]):[0-5]\d:[0-5]\d(\.\d+)?Z$"#
        let regex = try NSRegularExpression(pattern: pattern)
        let json = try encodeToJSONObject(makeFixtureDTO())
        let capturedAt = try XCTUnwrap(json["capturedAt"] as? String)
        let range = NSRange(capturedAt.startIndex..., in: capturedAt)
        XCTAssertNotNil(regex.firstMatch(in: capturedAt, range: range), "capturedAt '\(capturedAt)' must match the backend's datetime() regex")
    }

    // MARK: - polygonCorners: nullable(), NOT optional() — the key must
    // always be present, as an array or an explicit JSON null, never
    // omitted. Swift's default Codable synthesis (encodeIfPresent) would
    // OMIT the key for a nil Optional, which the backend's Zod schema
    // rejects (missing key is `undefined`, which `.nullable()` does not
    // accept). ScanSurfaceDTO's custom Codable conformance exists
    // specifically to avoid that; these two tests are a regression guard
    // for it.

    func testPolygonCornersEncodesExplicitNullWhenAbsent() throws {
        let json = try encodeToJSONObject(makeFixtureDTO(polygonCorners: nil))
        let surfaces = try XCTUnwrap(json["surfaces"] as? [[String: Any]])
        let surface = try XCTUnwrap(surfaces.first)

        XCTAssertTrue(surface.keys.contains("polygonCorners"), "polygonCorners key must be present even when there is no polygon")
        XCTAssertTrue(surface["polygonCorners"] is NSNull, "a missing polygon must serialize as JSON null, not an absent key")
    }

    func testPolygonCornersEncodesArrayWhenPresent() throws {
        let corners = [
            ScanPointDTO(x: 0, y: 0, z: 0),
            ScanPointDTO(x: 1, y: 0, z: 0),
            ScanPointDTO(x: 1, y: 0, z: 1),
        ]
        let json = try encodeToJSONObject(makeFixtureDTO(polygonCorners: corners))
        let surfaces = try XCTUnwrap(json["surfaces"] as? [[String: Any]])
        let polygon = try XCTUnwrap(surfaces.first?["polygonCorners"] as? [[String: Any]])

        XCTAssertEqual(polygon.count, 3, "backend requires at least 3 points when polygonCorners is not null")
        XCTAssertEqual(polygon[1]["x"] as? Double, 1)
    }

    // MARK: - device.osVersion / device.roomPlanVersion: optional(), not
    // nullable() — a nil value must OMIT the key entirely (the opposite of
    // polygonCorners above). Default Codable synthesis is correct here, so
    // this guards against ever "fixing" it the wrong way by analogy with
    // polygonCorners.

    func testOptionalDeviceFieldsAreOmittedWhenNil() throws {
        let json = try encodeToJSONObject(makeFixtureDTO(osVersion: nil, roomPlanVersion: nil))
        let device = try XCTUnwrap(json["device"] as? [String: Any])

        XCTAssertFalse(device.keys.contains("osVersion"), "optional() fields must be omitted, not sent as null")
        XCTAssertFalse(device.keys.contains("roomPlanVersion"))
        XCTAssertEqual(device["model"] as? String, "iPhone15,3")
    }

    func testOptionalDeviceFieldsAreIncludedWhenPresent() throws {
        let json = try encodeToJSONObject(makeFixtureDTO(osVersion: "17.4", roomPlanVersion: "2"))
        let device = try XCTUnwrap(json["device"] as? [String: Any])

        XCTAssertEqual(device["osVersion"] as? String, "17.4")
        XCTAssertEqual(device["roomPlanVersion"] as? String, "2")
    }

    // MARK: - transform: exactly 16 numbers

    func testTransformEncodesExactly16Numbers() throws {
        let json = try encodeToJSONObject(makeFixtureDTO())
        let surfaces = try XCTUnwrap(json["surfaces"] as? [[String: Any]])
        let transform = try XCTUnwrap(surfaces.first?["transform"] as? [Any])
        XCTAssertEqual(transform.count, 16, "back/src/scan-dto.ts requires exactly 16 numbers (4x4, column-major)")
    }

    // MARK: - Enum raw values must match the backend's Zod enums verbatim

    func testSurfaceKindRawValuesMatchBackendEnum() {
        let expected: Set<String> = ["floor", "wall", "door", "window", "opening"]
        let actual = Set([
            ScanSurfaceKindDTO.floor, .wall, .door, .window, .opening,
        ].map(\.rawValue))
        XCTAssertEqual(actual, expected, "must match scanSurfaceKindSchema in back/src/scan-dto.ts")
    }

    func testConfidenceRawValuesMatchBackendEnum() {
        let expected: Set<String> = ["low", "medium", "high"]
        let actual = Set([ScanConfidenceDTO.low, .medium, .high].map(\.rawValue))
        XCTAssertEqual(actual, expected, "must match scanConfidenceSchema in back/src/scan-dto.ts")
    }

    func testObjectCategoryRawValuesMatchBackendEnum() {
        // Must equal scanObjectCategorySchema in back/src/scan-dto.ts
        // exactly: RoomPlan's 16 CapturedRoom.Object.Category cases plus
        // "unknown" for anything this build doesn't recognize.
        let expected: Set<String> = [
            "storage", "refrigerator", "stove", "bed", "sink", "washerDryer",
            "toilet", "bathtub", "oven", "dishwasher", "table", "sofa",
            "chair", "fireplace", "television", "stairs", "unknown",
        ]
        let actual = Set(
            [
                ScanObjectCategoryDTO.storage, .refrigerator, .stove, .bed, .sink, .washerDryer,
                .toilet, .bathtub, .oven, .dishwasher, .table, .sofa,
                .chair, .fireplace, .television, .stairs, .unknown,
            ].map(\.rawValue)
        )
        XCTAssertEqual(actual, expected)
    }

    // MARK: - Round trip

    func testEncodeDecodeRoundTripPreservesValue() throws {
        let original = makeFixtureDTO()
        let data = try ScanDTOEncoding.makeEncoder().encode(original)
        let decoded = try ScanDTOEncoding.makeDecoder().decode(ScanUploadDTO.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testEncodeDecodeRoundTripWithNilPolygonAndOptionalFields() throws {
        let original = makeFixtureDTO(polygonCorners: nil, osVersion: nil, roomPlanVersion: nil)
        let data = try ScanDTOEncoding.makeEncoder().encode(original)
        let decoded = try ScanDTOEncoding.makeDecoder().decode(ScanUploadDTO.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    // MARK: - Required numeric fields are finite (backend requires
    // z.number().finite() throughout)

    func testDimensionsAndTransformAreFiniteNumbers() throws {
        let json = try encodeToJSONObject(makeFixtureDTO())
        let surfaces = try XCTUnwrap(json["surfaces"] as? [[String: Any]])
        let transform = try XCTUnwrap(surfaces.first?["transform"] as? [NSNumber])
        for value in transform {
            XCTAssertTrue(value.doubleValue.isFinite)
        }
        let dimensions = try XCTUnwrap(surfaces.first?["dimensions"] as? [String: NSNumber])
        for key in ["width", "height", "length"] {
            XCTAssertTrue(try XCTUnwrap(dimensions[key]).doubleValue.isFinite)
        }
    }

    // MARK: - Debug-only demo scan fixture (see DemoScanFixture.swift):
    // the exact same strictness applies to it as to a real RoomPlan-derived
    // DTO, since it goes through the same APIClient.uploadScan /
    // POST /api/scans path.

    func testDemoScanFixtureMatchesBackendSchemaShape() throws {
        let storeId = UUID()
        let targetLayoutId = UUID()
        let dto = DemoScanFixture.makeUploadDTO(scanId: fixtureScanId, storeId: storeId, targetLayoutId: targetLayoutId)
        let json = try encodeToJSONObject(dto)

        XCTAssertEqual(json["dtoVersion"] as? Int, 1)
        XCTAssertEqual(json["scanId"] as? String, fixtureScanId.uuidString)
        XCTAssertEqual(json["storeId"] as? String, storeId.uuidString)
        XCTAssertEqual(json["targetLayoutId"] as? String, targetLayoutId.uuidString)
        XCTAssertEqual(json["units"] as? String, "meters")

        let surfaces = try XCTUnwrap(json["surfaces"] as? [[String: Any]])
        XCTAssertFalse(surfaces.isEmpty)
        for surface in surfaces {
            XCTAssertTrue(surface.keys.contains("polygonCorners"), "polygonCorners must always be present (null or array)")
            let transform = try XCTUnwrap(surface["transform"] as? [Any])
            XCTAssertEqual(transform.count, 16)
        }

        let objects = try XCTUnwrap(json["objects"] as? [[String: Any]])
        XCTAssertFalse(objects.isEmpty)

        // Must be unmistakably non-real data, using only fields the frozen
        // contract already permits as free text (never an invented field).
        let device = try XCTUnwrap(json["device"] as? [String: Any])
        let model = try XCTUnwrap(device["model"] as? String)
        XCTAssertTrue(model.localizedCaseInsensitiveContains("demo"), "demo fixture must be clearly labeled as non-real in device.model")
    }

    func testDemoScanFixtureFloorHasAtLeastThreePolygonCorners() throws {
        let dto = DemoScanFixture.makeUploadDTO(scanId: fixtureScanId, storeId: UUID(), targetLayoutId: nil)
        let floor = try XCTUnwrap(dto.surfaces.first { $0.kind == .floor })
        let corners = try XCTUnwrap(floor.polygonCorners)
        XCTAssertGreaterThanOrEqual(corners.count, 3)
    }

    func testDemoScanFixtureAcceptsNilTargetLayoutId() throws {
        let dto = DemoScanFixture.makeUploadDTO(scanId: fixtureScanId, storeId: UUID(), targetLayoutId: nil)
        let json = try encodeToJSONObject(dto)
        XCTAssertTrue(json["targetLayoutId"] is NSNull, "nullable(), not optional(): nil must encode as explicit JSON null")
    }

    func testDemoScanFixtureRoundTripsThroughCodable() throws {
        let original = DemoScanFixture.makeUploadDTO(scanId: fixtureScanId, storeId: UUID(), targetLayoutId: UUID())
        let data = try ScanDTOEncoding.makeEncoder().encode(original)
        let decoded = try ScanDTOEncoding.makeDecoder().decode(ScanUploadDTO.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}
