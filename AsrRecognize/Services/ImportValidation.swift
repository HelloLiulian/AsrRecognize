import Foundation

enum ImportValidation {
    static let maxDuration: TimeInterval = 7_200
    static let maxFileSize: Int64 = 1_500_000_000

    enum Failure: LocalizedError, Equatable {
        case tooLong
        case tooLarge
        case invalid
        case insufficientSpace

        var errorDescription: String? {
            switch self {
            case .tooLong:
                return "Die Audiodatei ist länger als 2 Stunden."
            case .tooLarge:
                return "Die Audiodatei ist zu groß (maximal 1,5 GB)."
            case .invalid:
                return "Die Audiodatei konnte nicht gelesen werden."
            case .insufficientSpace:
                return "Nicht genügend Speicherplatz für die Audiodatei."
            }
        }
    }

    static func validate(duration: TimeInterval, fileSize: Int64) throws {
        guard duration > 0 else { throw Failure.invalid }
        guard duration <= maxDuration else { throw Failure.tooLong }
        guard fileSize <= maxFileSize else { throw Failure.tooLarge }
    }

    /// `required` is the total disk footprint for the import, not just the source file; callers include copy/working-space headroom.
    static func validateAvailableSpace(required: Int64, available: Int64?) throws {
        guard let available else { return }
        guard available >= required else { throw Failure.insufficientSpace }
    }
}
