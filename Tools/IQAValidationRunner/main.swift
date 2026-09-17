import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
#if canImport(ImageIO)
import ImageIO
#endif
#if canImport(WeddingCullCore)
import WeddingCullCore
#endif

// MARK: - Benchmark Math Utilities

enum IQAMath {
    static func rank<T: Comparable>(_ array: [T]) -> [Double] {
        let n = array.count
        guard n > 0 else { return [] }
        let indexed = array.enumerated().sorted { $0.element < $1.element }
        var ranks = [Double](repeating: 0.0, count: n)

        var i = 0
        while i < n {
            var j = i
            while j < n - 1 && indexed[j].element == indexed[j + 1].element {
                j += 1
            }
            let avgRank = Double(i + j + 2) / 2.0
            for k in i...j {
                ranks[indexed[k].offset] = avgRank
            }
            i = j + 1
        }
        return ranks
    }

    static func spearmanRho(x: [Double], y: [Double]) -> Double {
        guard x.count == y.count && x.count > 1 else { return 0.0 }
        let rx = rank(x)
        let ry = rank(y)
        return pearson(rx, ry)
    }

    static func pearson(_ x: [Double], _ y: [Double]) -> Double {
        let n = Double(x.count)
        guard n > 1 else { return 0.0 }
        let meanX = x.reduce(0, +) / n
        let meanY = y.reduce(0, +) / n

        var cov = 0.0
        var varX = 0.0
        var varY = 0.0
        for i in 0..<x.count {
            let dx = x[i] - meanX
            let dy = y[i] - meanY
            cov += dx * dy
            varX += dx * dx
            varY += dy * dy
        }
        let denom = sqrt(varX * varY)
        guard denom > 1e-9 else { return 0.0 }
        return max(-1.0, min(1.0, cov / denom))
    }

    static func pairwiseAccuracy(predicted: [Double], groundTruth: [Double], margin: Double = 0.05) -> Double {
        let n = predicted.count
        guard n > 1 && n == groundTruth.count else { return 0.0 }

        var correct = 0
        var total = 0

        for i in 0..<(n - 1) {
            for j in (i + 1)..<n {
                let diffGT = groundTruth[i] - groundTruth[j]
                if abs(diffGT) < margin { continue } // Skip ambiguous pairs

                let diffPred = predicted[i] - predicted[j]
                total += 1
                if (diffGT > 0 && diffPred > 0) || (diffGT < 0 && diffPred < 0) {
                    correct += 1
                }
            }
        }
        return total > 0 ? Double(correct) / Double(total) : 0.0
    }

    static func quantileSeparation(predicted: [Double], groundTruth: [Double], quantile: Double = 0.20) -> (topMean: Double, bottomMean: Double, separation: Double) {
        let n = predicted.count
        guard n >= 5 && n == groundTruth.count else { return (0.0, 0.0, 0.0) }

        let indexed = groundTruth.enumerated().sorted { $0.element < $1.element }
        let qCount = max(1, Int(Double(n) * quantile))

        let bottomIndices = indexed.prefix(qCount).map { $0.offset }
        let topIndices = indexed.suffix(qCount).map { $0.offset }

        let bottomMean = bottomIndices.map { predicted[$0] }.reduce(0, +) / Double(bottomIndices.count)
        let topMean = topIndices.map { predicted[$0] }.reduce(0, +) / Double(topIndices.count)

        return (topMean, bottomMean, topMean - bottomMean)
    }
}

// MARK: - Main Execution

@main
struct IQAValidationRunner {
    struct IQAReport: Codable {
        let timestamp: String
        let dataset: String
        let status: String
        let message: String
        let totalSamplesEvaluated: Int
        let spearmanCorrelationOverall: Double?
        let pearsonCorrelationOverall: Double?
        let sharpnessCorrelation: Double?
        let pairwiseRankingAccuracy: Double?
        let topQuantileMeanScore: Double?
        let bottomQuantileMeanScore: Double?
        let quantileSeparation: Double?
    }

    static func main() async {
        let args = CommandLine.arguments

        var datasetType = "spaq"
        var datasetDir: String? = nil
        var outputPath = "artifacts/iqa-report.json"

        var i = 1
        while i < args.count {
            switch args[i] {
            case "--dataset":
                if i + 1 < args.count {
                    datasetType = args[i + 1].lowercased()
                    i += 1
                }
            case "--dataset-dir":
                if i + 1 < args.count {
                    datasetDir = args[i + 1]
                    i += 1
                }
            case "--output":
                if i + 1 < args.count {
                    outputPath = args[i + 1]
                    i += 1
                }
            default:
                break
            }
            i += 1
        }

        print("====================================================")
        print("🔍 WeddingCull Image Quality Assessment (IQA) Benchmark")
        print("====================================================")
        print("Dataset requested: \(datasetType)")

        let fm = FileManager.default

        guard let dir = datasetDir, fm.fileExists(atPath: dir) else {
            print("ℹ️ Dataset directory not specified or does not exist.")
            print("ℹ️ Due to academic/commercial redistribution licenses, public CI does not bundle multi-GB IQA datasets.")
            print("ℹ️ Status: NOT_VERIFIED_IN_PUBLIC_CI")

            let unverifiedReport = IQAReport(
                timestamp: ISO8601DateFormatter().string(from: Date()),
                dataset: datasetType.uppercased(),
                status: "NOT_VERIFIED_IN_PUBLIC_CI",
                message: "Dataset directory not supplied or not present on public CI runner. To evaluate locally: download \(datasetType.uppercased()) dataset and run with --dataset-dir <PATH>",
                totalSamplesEvaluated: 0,
                spearmanCorrelationOverall: nil,
                pearsonCorrelationOverall: nil,
                sharpnessCorrelation: nil,
                pairwiseRankingAccuracy: nil,
                topQuantileMeanScore: nil,
                bottomQuantileMeanScore: nil,
                quantileSeparation: nil
            )

            writeJSON(unverifiedReport, to: outputPath)
            exit(0)
        }

        // Parse dataset annotations and image files
        // Format convention: annotations.csv or labels.json in datasetDir
        print("📂 Scanning \(dir) for \(datasetType.uppercased()) dataset annotations...")

        var samples: [(fileURL: URL, mos: Double)] = []

        let csvURL = URL(fileURLWithPath: dir).appendingPathComponent("annotations.csv")
        let jsonURL = URL(fileURLWithPath: dir).appendingPathComponent("labels.json")

        if fm.fileExists(atPath: csvURL.path), let content = try? String(contentsOf: csvURL) {
            let lines = content.components(separatedBy: .newlines)
            for line in lines.dropFirst() {
                let parts = line.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
                if parts.count >= 2, let mos = Double(parts[1]) {
                    let imgURL = URL(fileURLWithPath: dir).appendingPathComponent(parts[0])
                    if fm.fileExists(atPath: imgURL.path) {
                        samples.append((imgURL, mos))
                    }
                }
            }
        } else if fm.fileExists(atPath: jsonURL.path),
                  let data = try? Data(contentsOf: jsonURL),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Double] {
            for (filename, mos) in dict {
                let imgURL = URL(fileURLWithPath: dir).appendingPathComponent(filename)
                if fm.fileExists(atPath: imgURL.path) {
                    samples.append((imgURL, mos))
                }
            }
        }

        guard !samples.isEmpty else {
            print("⚠️ No annotated image pairs found in \(dir). Expected annotations.csv or labels.json.")
            let emptyReport = IQAReport(
                timestamp: ISO8601DateFormatter().string(from: Date()),
                dataset: datasetType.uppercased(),
                status: "NOT_VERIFIED",
                message: "No valid image + MOS annotations found in provided directory.",
                totalSamplesEvaluated: 0,
                spearmanCorrelationOverall: nil,
                pearsonCorrelationOverall: nil,
                sharpnessCorrelation: nil,
                pairwiseRankingAccuracy: nil,
                topQuantileMeanScore: nil,
                bottomQuantileMeanScore: nil,
                quantileSeparation: nil
            )
            writeJSON(emptyReport, to: outputPath)
            exit(0)
        }

        print("Evaluating \(samples.count) images with TechnicalQualityAnalyzer...")
        let analyzer = TechnicalQualityAnalyzer()

        var predictedScores: [Double] = []
        var sharpnessScores: [Double] = []
        var groundTruthMOS: [Double] = []

        for (u, mos) in samples {
            guard let src = CGImageSourceCreateWithURL(u as CFURL, nil),
                  let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
                continue
            }
            let res = analyzer.analyze(cgImage: cg)
            let rawSharp = res.rawSharpness
            let exp = 1.0 - (abs(res.meanLuminance - 0.5) * 2.0 * 0.4 + (res.shadowClipping + res.highlightClipping) * 0.6)
            let overall = max(0.0, min(1.0, (rawSharp / 500.0) * 0.6 + exp * 0.4))

            predictedScores.append(overall)
            sharpnessScores.append(rawSharp)
            groundTruthMOS.append(mos)
        }

        let spearman = IQAMath.spearmanRho(x: predictedScores, y: groundTruthMOS)
        let pearson = IQAMath.pearson(predictedScores, groundTruthMOS)
        let sharpCorr = IQAMath.spearmanRho(x: sharpnessScores, y: groundTruthMOS)
        let pairwise = IQAMath.pairwiseAccuracy(predicted: predictedScores, groundTruth: groundTruthMOS)
        let qSep = IQAMath.quantileSeparation(predicted: predictedScores, groundTruth: groundTruthMOS)

        print("\n====================================================")
        print("📊 IQA EVALUATION RESULTS (\(datasetType.uppercased()))")
        print("====================================================")
        print("Samples: \(predictedScores.count)")
        print(String(format: "Spearman Rank Correlation (SRCC): %.3f", spearman))
        print(String(format: "Pearson Linear Correlation (PLCC): %.3f", pearson))
        print(String(format: "Sharpness vs MOS Correlation: %.3f", sharpCorr))
        print(String(format: "Pairwise Ranking Accuracy: %.1f%%", pairwise * 100))
        print(String(format: "Top Quantile Mean Score: %.3f", qSep.topMean))
        print(String(format: "Bottom Quantile Mean Score: %.3f", qSep.bottomMean))
        print(String(format: "Quantile Separation: %.3f", qSep.separation))
        print("====================================================")

        let report = IQAReport(
            timestamp: ISO8601DateFormatter().string(from: Date()),
            dataset: datasetType.uppercased(),
            status: "EXECUTED",
            message: "Successfully evaluated on \(predictedScores.count) annotated \(datasetType.uppercased()) images.",
            totalSamplesEvaluated: predictedScores.count,
            spearmanCorrelationOverall: spearman,
            pearsonCorrelationOverall: pearson,
            sharpnessCorrelation: sharpCorr,
            pairwiseRankingAccuracy: pairwise,
            topQuantileMeanScore: qSep.topMean,
            bottomQuantileMeanScore: qSep.bottomMean,
            quantileSeparation: qSep.separation
        )

        writeJSON(report, to: outputPath)
        print("✅ Written IQA report to \(outputPath)")
    }

    static func writeJSON<T: Encodable>(_ obj: T, to path: String) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(obj) {
            let url = URL(fileURLWithPath: path)
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url)
        }
    }
}
