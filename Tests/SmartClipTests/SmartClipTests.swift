import XCTest
@testable import SmartClip

final class SmartClipTests: XCTestCase {
    @MainActor
    func testPlanCoverage() async throws {
        // Shared with the CLT-compatible runner; it runs every case and reports
        // all failures instead of stopping at the first assertion.
        try await runCoreChecks()
    }
}
