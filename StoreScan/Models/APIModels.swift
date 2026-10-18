import Foundation

// Mirrors the subset of back/src/index.ts's JSON responses this app reads.
// Field names match front/src/lib/types.ts exactly (the web app's own
// mirror of the same backend), not invented independently.

struct LayoutSummary: Codable, Identifiable, Equatable {
    var id: UUID
    var storeId: UUID
    var name: String
    var widthCm: Int
    var depthCm: Int
}

struct Store: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var address: String
    var layouts: [LayoutSummary]
}

struct StoresResponse: Codable {
    var stores: [Store]
}

// POST /api/auth/sign-in/email (Better Auth). The bearer plugin returns the
// token in the response body's "token" field — the same field the web
// app's own auth.test.ts reads (`loginBody.token`) to exercise the
// Authorization: Bearer flow, rather than parsing the `set-auth-token`
// response header.
struct SignInUser: Codable, Equatable {
    var id: String
    var name: String
    var email: String
}

struct SignInResponse: Codable {
    var token: String?
    var user: SignInUser?
}

// Better Auth's generic error shape, e.g. {"error":"Invalid email or password"}
// or {"message": "..."} depending on the failure. Both are checked.
struct APIErrorBody: Codable {
    var error: String?
    var message: String?
}

// POST /api/scans response: { scan: { id, status, ... } }. Only the fields
// this app actually uses are modeled; the backend may return more.
struct ScanDraftSummary: Codable {
    var id: UUID
    var status: String
}

struct ScanUploadResponse: Codable {
    var scan: ScanDraftSummary
}
