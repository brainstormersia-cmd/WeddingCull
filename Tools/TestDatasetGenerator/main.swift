import Foundation
#if canImport(TestDatasetGeneratorLibrary)
import TestDatasetGeneratorLibrary
#endif

let arguments = ProcessInfo.processInfo.arguments
let outputDir: URL

if arguments.count > 1 {
    outputDir = URL(fileURLWithPath: arguments[1])
} else {
    outputDir = URL(fileURLWithPath: "./test_wedding_dataset")
}

print("Generating synthetic wedding dataset at: \(outputDir.path)...")
let generator = SyntheticWeddingGenerator()
do {
    let files = try generator.generateDataset(at: outputDir)
    print("Successfully generated \(files.count) synthetic wedding photos.")
} catch {
    print("Error generating dataset: \(error)")
    exit(1)
}
