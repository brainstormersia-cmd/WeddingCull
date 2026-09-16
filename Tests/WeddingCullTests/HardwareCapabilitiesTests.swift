import XCTest
@testable import WeddingCull

final class HardwareCapabilitiesTests: XCTestCase {
    func testHardwareDetection() {
        let hardware = HardwareCapabilities()
        XCTAssertFalse(hardware.cpuArchitecture.isEmpty, "Architecture must not be empty")
        XCTAssertGreaterThan(hardware.logicalProcessors, 0, "Logical processors must be > 0")
        XCTAssertGreaterThan(hardware.physicalMemoryBytes, 0, "Physical memory must be > 0")
        XCTAssertGreaterThan(hardware.recommendedConcurrency, 0, "Concurrency must be > 0")

        if hardware.isAppleSilicon {
            XCTAssertEqual(hardware.recommendedProfile, .advanced)
        } else {
            XCTAssertEqual(hardware.recommendedProfile, .basic)
        }
    }
}
