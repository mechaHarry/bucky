import XCTest
@testable import Bucky

@available(macOS 26.0, *)
final class LauncherFilterPerformanceSupportTests: XCTestCase {
    func testComfortBandClassifiesFasterAndSmallSlowdownsAsComfort() {
        XCTAssertEqual(
            LauncherFilterPerformanceComparison.classify(
                baselineMilliseconds: 10,
                currentMilliseconds: 9,
                comfortThresholdPercent: 5,
                regressionThresholdPercent: 15
            ).band,
            .comfort
        )
        XCTAssertEqual(
            LauncherFilterPerformanceComparison.classify(
                baselineMilliseconds: 10,
                currentMilliseconds: 10.5,
                comfortThresholdPercent: 5,
                regressionThresholdPercent: 15
            ).band,
            .comfort
        )
    }

    func testComfortBandClassifiesMiddleSlowdownsAsWatch() {
        XCTAssertEqual(
            LauncherFilterPerformanceComparison.classify(
                baselineMilliseconds: 10,
                currentMilliseconds: 11,
                comfortThresholdPercent: 5,
                regressionThresholdPercent: 15
            ).band,
            .watch
        )
    }

    func testComfortBandClassifiesLargeSlowdownsAsRegression() {
        XCTAssertEqual(
            LauncherFilterPerformanceComparison.classify(
                baselineMilliseconds: 10,
                currentMilliseconds: 11.6,
                comfortThresholdPercent: 5,
                regressionThresholdPercent: 15
            ).band,
            .regression
        )
    }

    func testBaselineRejectsInvalidDurations() {
        let baseline = LauncherFilterPerformanceBaseline(
            benchmarkName: "launcher-filter",
            baselineMedianMilliseconds: 0,
            sampleCount: 7,
            workloadItemCount: 1_200,
            workloadQueryCount: 8,
            comfortThresholdPercent: 5,
            regressionThresholdPercent: 15,
            capturedAt: "2026-05-01T00:00:00Z",
            gitCommit: "abc123"
        )

        XCTAssertThrowsError(try baseline.validate())
    }

    func testBaselineEncodingContainsMetricFields() throws {
        let baseline = LauncherFilterPerformanceBaseline(
            benchmarkName: "launcher-filter",
            baselineMedianMilliseconds: 12.5,
            sampleCount: 7,
            workloadItemCount: 1_200,
            workloadQueryCount: 8,
            comfortThresholdPercent: 5,
            regressionThresholdPercent: 15,
            capturedAt: "2026-05-01T00:00:00Z",
            gitCommit: "abc123"
        )

        let data = try LauncherFilterPerformanceBaselineCodec.encode(baseline)
        let json = String(decoding: data, as: UTF8.self)

        XCTAssertTrue(json.contains("\"benchmarkName\" : \"launcher-filter\""))
        XCTAssertTrue(json.contains("\"baselineMedianMilliseconds\" : 12.5"))
        XCTAssertTrue(json.contains("\"workloadItemCount\" : 1200"))
    }
}

@available(macOS 26.0, *)
enum LauncherFilterPerformanceBand: String, Codable, Equatable {
    case comfort
    case watch
    case regression
}

@available(macOS 26.0, *)
struct LauncherFilterPerformanceComparison: Equatable {
    let baselineMilliseconds: Double
    let currentMilliseconds: Double
    let deltaPercent: Double
    let band: LauncherFilterPerformanceBand

    static func classify(
        baselineMilliseconds: Double,
        currentMilliseconds: Double,
        comfortThresholdPercent: Double,
        regressionThresholdPercent: Double
    ) -> LauncherFilterPerformanceComparison {
        let deltaPercent = ((currentMilliseconds - baselineMilliseconds) / baselineMilliseconds) * 100
        let band: LauncherFilterPerformanceBand
        if deltaPercent > regressionThresholdPercent {
            band = .regression
        } else if deltaPercent > comfortThresholdPercent {
            band = .watch
        } else {
            band = .comfort
        }
        return LauncherFilterPerformanceComparison(
            baselineMilliseconds: baselineMilliseconds,
            currentMilliseconds: currentMilliseconds,
            deltaPercent: deltaPercent,
            band: band
        )
    }
}

@available(macOS 26.0, *)
struct LauncherFilterPerformanceBaseline: Codable, Equatable {
    let benchmarkName: String
    let baselineMedianMilliseconds: Double
    let sampleCount: Int
    let workloadItemCount: Int
    let workloadQueryCount: Int
    let comfortThresholdPercent: Double
    let regressionThresholdPercent: Double
    let capturedAt: String
    let gitCommit: String?

    func validate() throws {
        if baselineMedianMilliseconds <= 0 {
            throw LauncherFilterPerformanceError.invalidBaseline("baselineMedianMilliseconds must be greater than zero")
        }
        if sampleCount <= 0 {
            throw LauncherFilterPerformanceError.invalidBaseline("sampleCount must be greater than zero")
        }
        if workloadItemCount <= 0 {
            throw LauncherFilterPerformanceError.invalidBaseline("workloadItemCount must be greater than zero")
        }
        if workloadQueryCount <= 0 {
            throw LauncherFilterPerformanceError.invalidBaseline("workloadQueryCount must be greater than zero")
        }
    }
}

@available(macOS 26.0, *)
enum LauncherFilterPerformanceError: Error, Equatable, CustomStringConvertible {
    case invalidBaseline(String)
    case missingBaseline(String)
    case malformedBaseline(String)
    case baselineWriteFailed(String)

    var description: String {
        switch self {
        case .invalidBaseline(let message):
            return message
        case .missingBaseline(let message):
            return message
        case .malformedBaseline(let message):
            return message
        case .baselineWriteFailed(let message):
            return message
        }
    }
}

@available(macOS 26.0, *)
enum LauncherFilterPerformanceBaselineCodec {
    static func encode(_ baseline: LauncherFilterPerformanceBaseline) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(baseline)
    }

    static func decode(_ data: Data) throws -> LauncherFilterPerformanceBaseline {
        try JSONDecoder().decode(LauncherFilterPerformanceBaseline.self, from: data)
    }
}
