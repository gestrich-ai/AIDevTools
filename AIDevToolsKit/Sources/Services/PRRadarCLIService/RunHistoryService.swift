import Foundation
import PRRadarConfigService
import PRRadarModelsService

public struct RunHistoryEntry: Sendable {
    public let manifest: RunManifest
    public let prEntries: [RunAllPREntry]

    public init(manifest: RunManifest, prEntries: [RunAllPREntry]) {
        self.manifest = manifest
        self.prEntries = prEntries
    }
}

public struct RunHistoryService {
    public static func loadRuns(outputDir: String, limit: Int = 50) throws -> [RunHistoryEntry] {
        let runsDir = "\(outputDir)/runs"
        let fm = FileManager.default

        guard fm.fileExists(atPath: runsDir) else {
            return []
        }

        let files = try fm.contentsOfDirectory(atPath: runsDir)
            .filter { $0.hasSuffix(".json") }
            .sorted()
            .reversed()
            .prefix(limit)

        let decoder = JSONDecoder()
        var entries: [RunHistoryEntry] = []

        for filename in files {
            let path = "\(runsDir)/\(filename)"
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let manifest = try? decoder.decode(RunManifest.self, from: data) else {
                continue
            }

            let prEntries = manifest.prs.map { entry in
                RunAllPREntry(
                    entry: entry,
                    summary: loadReportSummary(outputDir: outputDir, prNumber: entry.prNumber)
                )
            }

            entries.append(RunHistoryEntry(manifest: manifest, prEntries: prEntries))
        }

        return entries
    }

    public static func loadReportSummary(outputDir: String, prNumber: Int) -> ReportSummary? {
        let decoder = JSONDecoder()

        let metadataResultPath = PRRadarPhasePaths.phaseDirectory(
            outputDir: outputDir, prNumber: prNumber, phase: .metadata
        ) + "/\(PRRadarPhasePaths.phaseResultFilename)"

        if let metaData = try? Data(contentsOf: URL(fileURLWithPath: metadataResultPath)),
           let metaResult = try? decoder.decode(PhaseResult.self, from: metaData),
           let commitHash = metaResult.stats?.metadata?["commitHash"] {
            let reportPath = PRRadarPhasePaths.phaseDirectory(
                outputDir: outputDir, prNumber: prNumber, phase: .report, commitHash: commitHash
            ) + "/\(PRRadarPhasePaths.summaryJSONFilename)"
            if let reportData = try? Data(contentsOf: URL(fileURLWithPath: reportPath)),
               let report = try? decoder.decode(ReviewReport.self, from: reportData) {
                return report.summary
            }
        }

        // Fallback: scan analysis/ subdirectories for any report/summary.json
        let analysisDir = "\(outputDir)/\(prNumber)/\(PRRadarPhasePaths.analysisDirectoryName)"
        if let commits = try? FileManager.default.contentsOfDirectory(atPath: analysisDir) {
            for commit in commits.sorted().reversed() {
                let reportPath = "\(analysisDir)/\(commit)/\(PRRadarPhase.report.rawValue)/\(PRRadarPhasePaths.summaryJSONFilename)"
                if let reportData = try? Data(contentsOf: URL(fileURLWithPath: reportPath)),
                   let report = try? decoder.decode(ReviewReport.self, from: reportData) {
                    return report.summary
                }
            }
        }

        return nil
    }
}
