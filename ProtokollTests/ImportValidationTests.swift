import XCTest
@testable import ProtokollLogic

final class ImportValidationTests: XCTestCase {
    func testAcceptsTwoHours() throws {
        XCTAssertNoThrow(try ImportValidation.validate(duration: 7_200, fileSize: 1_000_000))
    }

    func testRejectsTooLong() {
        XCTAssertThrowsError(try ImportValidation.validate(duration: 7_201, fileSize: 1_000_000)) { error in
            XCTAssertEqual((error as? ImportValidation.Failure), .tooLong)
        }
    }

    func testRejectsTooLarge() {
        XCTAssertThrowsError(try ImportValidation.validate(duration: 60, fileSize: 1_500_000_001)) { error in
            XCTAssertEqual((error as? ImportValidation.Failure), .tooLarge)
        }
    }

    func testRejectsInvalidDuration() {
        XCTAssertThrowsError(try ImportValidation.validate(duration: 0, fileSize: 1_000)) { error in
            XCTAssertEqual((error as? ImportValidation.Failure), .invalid)
        }
    }

    func testRejectsNaNDuration() {
        XCTAssertThrowsError(try ImportValidation.validate(duration: .nan, fileSize: 1_000)) { error in
            XCTAssertEqual((error as? ImportValidation.Failure), .invalid)
        }
    }

    func testRejectsNegativeDuration() {
        XCTAssertThrowsError(try ImportValidation.validate(duration: -1, fileSize: 1_000)) { error in
            XCTAssertEqual((error as? ImportValidation.Failure), .invalid)
        }
    }

    func testAcceptsExactMaxFileSize() {
        XCTAssertNoThrow(try ImportValidation.validate(duration: 60, fileSize: 1_500_000_000))
    }

    func testAcceptsZeroByteFile() {
        XCTAssertNoThrow(try ImportValidation.validate(duration: 60, fileSize: 0))
    }

    func testRejectsInsufficientSpace() {
        XCTAssertThrowsError(
            try ImportValidation.validateAvailableSpace(required: 2_000_000_000, available: 1_000_000_000)
        ) { error in
            XCTAssertEqual((error as? ImportValidation.Failure), .insufficientSpace)
        }
    }

    func testMissingSpaceInformationIsAccepted() {
        XCTAssertNoThrow(try ImportValidation.validateAvailableSpace(required: 2_000_000_000, available: nil))
    }

    func testAcceptsExactAvailableSpace() {
        XCTAssertNoThrow(try ImportValidation.validateAvailableSpace(required: 1_000_000, available: 1_000_000))
    }
}
