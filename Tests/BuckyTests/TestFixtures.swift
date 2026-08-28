import Foundation

enum TestFixtures {
    static let userRoot = URL(fileURLWithPath: "/Users", isDirectory: true)
    static let userHome = URL(fileURLWithPath: "/Users/test", isDirectory: true)
    static let sampleCloudTargetName = "SampleCloudTarget"
    static let sampleCloudTargetDisplayName = "Sample Cloud Target"

    static func sampleCloudTargetDirectory(in directory: URL) -> URL {
        directory.appendingPathComponent(sampleCloudTargetName, isDirectory: true)
    }

    static func sampleCloudTargetLink(in directory: URL) -> URL {
        directory.appendingPathComponent(sampleCloudTargetDisplayName)
    }
}
