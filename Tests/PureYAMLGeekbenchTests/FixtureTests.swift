import Foundation
import Testing

@Suite("Fixture Corpus")
struct FixtureTests {
    @Test("real-world corpus contains at least 100 YAML files")
    func realWorldCorpusCount() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fixtureURL = rootURL
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("real-yaml")
        let files = try FileManager.default.contentsOfDirectory(
            at: fixtureURL,
            includingPropertiesForKeys: nil,
        ).filter { url in
            url.pathExtension == "yaml" || url.pathExtension == "yml"
        }

        #expect(files.count >= 100)
        #expect(files.count == 114)
    }

    @Test("corpus manifest is present")
    func manifestExists() {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let manifestURL = rootURL
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("real-yaml-corpus.yaml")

        #expect(FileManager.default.fileExists(atPath: manifestURL.path))
    }
}
