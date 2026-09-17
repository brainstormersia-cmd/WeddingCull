import Foundation
import Metal

public enum ProcessingProfile: String, Codable, Sendable {
    case basic
    case advanced
}

public struct HardwareCapabilities: Sendable {
    public let cpuArchitecture: String
    public let logicalProcessors: Int
    public let physicalMemoryBytes: UInt64
    public let isAppleSilicon: Bool
    public let neuralEngineAvailable: Bool
    public let metalAvailable: Bool
    public let recommendedProfile: ProcessingProfile
    public let concurrencyOverride: Int?

    public init(concurrencyOverride: Int? = nil) {
        var arch = "unknown"
        #if arch(arm64)
        arch = "arm64"
        let appleSilicon = true
        #elseif arch(x86_64)
        arch = "x86_64"
        let appleSilicon = false
        #else
        let appleSilicon = false
        #endif

        var systemInfo = utsname()
        if uname(&systemInfo) == 0 {
            let machineMirror = Mirror(reflecting: systemInfo.machine)
            let identifier = machineMirror.children.reduce("") { identifier, element in
                guard let value = element.value as? Int8, value != 0 else { return identifier }
                return identifier + String(UnicodeScalar(UInt8(value)))
            }
            if !identifier.isEmpty {
                arch = identifier
            }
        }

        self.cpuArchitecture = arch
        self.logicalProcessors = ProcessInfo.processInfo.processorCount
        self.physicalMemoryBytes = ProcessInfo.processInfo.physicalMemory
        self.isAppleSilicon = arch.contains("arm64") || appleSilicon
        self.neuralEngineAvailable = self.isAppleSilicon
        self.concurrencyOverride = concurrencyOverride

        if let defaultDevice = MTLCreateSystemDefaultDevice() {
            self.metalAvailable = true
            _ = defaultDevice
        } else {
            self.metalAvailable = false
        }

        if self.isAppleSilicon {
            self.recommendedProfile = .advanced
        } else {
            self.recommendedProfile = .basic
        }
    }

    public var memoryGB: Double {
        return Double(physicalMemoryBytes) / (1024.0 * 1024.0 * 1024.0)
    }

    public var recommendedConcurrency: Int {
        if let override = concurrencyOverride {
            return max(1, override)
        }
        let maxLimit = isAppleSilicon ? 8 : 4
        return max(2, min(logicalProcessors, maxLimit))
    }
}
