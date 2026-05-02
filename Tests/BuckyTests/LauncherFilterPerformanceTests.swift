import Foundation
import XCTest
@testable import Bucky

@available(macOS 26.0, *)
final class LauncherFilterPerformanceTests: XCTestCase {
    func testLauncherFilterPerformanceAgainstBaseline() throws {
        let runner = LauncherFilterPerformanceRunner()
        let updateBaseline = ProcessInfo.processInfo.environment["BUCKY_PERF_UPDATE_BASELINE"] == "1"
        let result = try runner.run(updateBaseline: updateBaseline)

        XCTAssertNotEqual(result.comparison.band, .regression, result.report)
    }
}

@available(macOS 26.0, *)
struct LauncherFilterPerformanceResult {
    let samplesMilliseconds: [Double]
    let comparison: LauncherFilterPerformanceComparison
    let report: String
}

@available(macOS 26.0, *)
final class LauncherFilterPerformanceRunner {
    private let benchmarkName = "launcher-filter"
    private let baselineRelativePath = ".agents/performance/launcher-filter-baseline.json"
    private let comfortThresholdPercent = 5.0
    private let regressionThresholdPercent = 15.0
    private let itemCount = 1_200
    private let warmupSampleCount = 5
    private let measuredSampleCount = 9
    private let queryLoopCount = 40

    func run(updateBaseline: Bool) throws -> LauncherFilterPerformanceResult {
        let workload = makeWorkload()
        runWarmup(workload)
        let samples = measureSamples(workload)
        let currentMedian = median(samples)

        let baseline: LauncherFilterPerformanceBaseline
        if updateBaseline {
            baseline = makeBaseline(currentMedianMilliseconds: currentMedian, workload: workload)
            try writeBaseline(baseline)
        } else {
            baseline = try loadBaseline()
        }

        try baseline.validate()
        let comparison = LauncherFilterPerformanceComparison.classify(
            baselineMilliseconds: baseline.baselineMedianMilliseconds,
            currentMilliseconds: currentMedian,
            comfortThresholdPercent: baseline.comfortThresholdPercent,
            regressionThresholdPercent: baseline.regressionThresholdPercent
        )
        let report = makeReport(
            baseline: baseline,
            samples: samples,
            comparison: comparison,
            updateBaseline: updateBaseline
        )
        print(report)

        return LauncherFilterPerformanceResult(
            samplesMilliseconds: samples,
            comparison: comparison,
            report: report
        )
    }

    private func makeWorkload() -> LauncherFilterPerformanceWorkload {
        let families = [
            "Notes",
            "Archive",
            "Calendar",
            "Mail",
            "Terminal",
            "System Settings",
            "Music",
            "Dictionary",
            "Calculator",
            "Preview",
            "Messages",
            "Reminders"
        ]
        let modifiers = [
            "Daily",
            "Workspace",
            "Personal",
            "Project",
            "Quick",
            "Classic",
            "Studio",
            "Reader"
        ]
        let items = (0..<itemCount).map { index in
            let family = families[index % families.count]
            let modifier = modifiers[(index / families.count) % modifiers.count]
            let title = "\(family) \(modifier) \(index)"
            return LaunchItem(
                title: title,
                subtitle: "/Applications/\(title).app",
                url: URL(fileURLWithPath: "/Applications/\(title).app"),
                searchText: normalized(title)
            )
        }
        return LauncherFilterPerformanceWorkload(
            items: items,
            queries: [
                "",
                "no",
                "notes",
                "notes project",
                "system set",
                "calc",
                "dictionary classic",
                "missing token"
            ]
        )
    }

    private func runWarmup(_ workload: LauncherFilterPerformanceWorkload) {
        for _ in 0..<warmupSampleCount {
            _ = measureSample(workload)
        }
    }

    private func measureSamples(_ workload: LauncherFilterPerformanceWorkload) -> [Double] {
        (0..<measuredSampleCount).map { _ in
            measureSample(workload)
        }
    }

    private func measureSample(_ workload: LauncherFilterPerformanceWorkload) -> Double {
        var checksum = 0
        let start = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<queryLoopCount {
            for query in workload.queries {
                checksum &+= LiquidGlassLauncherModel.filter(workload.items, normalizedQuery: query).count
            }
        }
        let end = DispatchTime.now().uptimeNanoseconds
        precondition(checksum >= 0)
        return Double(end - start) / 1_000_000
    }

    private func median(_ samples: [Double]) -> Double {
        let sorted = samples.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    private func makeBaseline(
        currentMedianMilliseconds: Double,
        workload: LauncherFilterPerformanceWorkload
    ) -> LauncherFilterPerformanceBaseline {
        LauncherFilterPerformanceBaseline(
            benchmarkName: benchmarkName,
            baselineMedianMilliseconds: currentMedianMilliseconds,
            sampleCount: measuredSampleCount,
            workloadItemCount: workload.items.count,
            workloadQueryCount: workload.queries.count,
            comfortThresholdPercent: comfortThresholdPercent,
            regressionThresholdPercent: regressionThresholdPercent,
            capturedAt: ISO8601DateFormatter().string(from: Date()),
            gitCommit: ProcessInfo.processInfo.environment["BUCKY_PERF_GIT_COMMIT"].flatMap { $0.isEmpty ? nil : $0 }
        )
    }

    private func loadBaseline() throws -> LauncherFilterPerformanceBaseline {
        let url = baselineURL()
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw LauncherFilterPerformanceError.missingBaseline(
                "Missing performance baseline at \(baselineRelativePath). Run `make perf-baseline` to capture it explicitly."
            )
        }

        do {
            let baseline = try LauncherFilterPerformanceBaselineCodec.decode(Data(contentsOf: url))
            try baseline.validate()
            return baseline
        } catch let error as LauncherFilterPerformanceError {
            throw error
        } catch {
            throw LauncherFilterPerformanceError.malformedBaseline(
                "Could not read performance baseline at \(baselineRelativePath): \(error)"
            )
        }
    }

    private func writeBaseline(_ baseline: LauncherFilterPerformanceBaseline) throws {
        do {
            try baseline.validate()
            let url = baselineURL()
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try LauncherFilterPerformanceBaselineCodec.encode(baseline).write(to: url, options: .atomic)
        } catch let error as LauncherFilterPerformanceError {
            throw error
        } catch {
            throw LauncherFilterPerformanceError.baselineWriteFailed(
                "Could not write performance baseline at \(baselineRelativePath): \(error)"
            )
        }
    }

    private func baselineURL() -> URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(baselineRelativePath)
    }

    private func makeReport(
        baseline: LauncherFilterPerformanceBaseline,
        samples: [Double],
        comparison: LauncherFilterPerformanceComparison,
        updateBaseline: Bool
    ) -> String {
        let minSample = samples.min() ?? comparison.currentMilliseconds
        let maxSample = samples.max() ?? comparison.currentMilliseconds
        let mode = updateBaseline ? "captured" : "checked"
        return String(
            format: "Bucky performance %@ %@: current median %.3f ms, baseline %.3f ms, delta %+.2f%%, band %@, samples min/median/max %.3f/%.3f/%.3f ms",
            benchmarkName,
            mode,
            comparison.currentMilliseconds,
            baseline.baselineMedianMilliseconds,
            comparison.deltaPercent,
            comparison.band.rawValue,
            minSample,
            comparison.currentMilliseconds,
            maxSample
        )
    }
}

@available(macOS 26.0, *)
private struct LauncherFilterPerformanceWorkload {
    let items: [LaunchItem]
    let queries: [String]
}
