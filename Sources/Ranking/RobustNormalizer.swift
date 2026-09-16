import Foundation

public struct RobustNormalizer: Sendable {
    public let p10: Double
    public let p90: Double
    public let median: Double

    public init(values: [Double]) {
        guard !values.isEmpty else {
            self.p10 = 0.0
            self.p90 = 1.0
            self.median = 0.5
            return
        }

        let sorted = values.sorted()
        let n = sorted.count

        let idx10 = max(0, min(n - 1, Int(Double(n) * 0.10)))
        let idx50 = max(0, min(n - 1, Int(Double(n) * 0.50)))
        let idx90 = max(0, min(n - 1, Int(Double(n) * 0.90)))

        self.p10 = sorted[idx10]
        self.median = sorted[idx50]
        let high = sorted[idx90]

        // Ensure range is non-zero
        if high > self.p10 {
            self.p90 = high
        } else {
            self.p90 = self.p10 + 1.0
        }
    }

    /// Normalizes a raw value to [0.0, 1.0] based on robust percentiles
    public func normalize(_ value: Double) -> Double {
        if value <= p10 { return 0.05 }
        if value >= p90 { return 1.0 }
        let norm = (value - p10) / (p90 - p10)
        return max(0.05, min(1.0, norm))
    }
}
