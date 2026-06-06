import Foundation
import PureYAML
import Yams
import YAML

struct ParserDefinition {
    var id: String
    var name: String
    var packagingScore: Double
    var diagnosticScore: Double
}

struct Seed {
    var id: String
    var localPath: String
    var category: String
    var size: String
    var tier: String
    var expectedParse: String
    var byteCount: Int
    var lineCount: Int
    var repository: String
    var commit: String
    var sourcePath: String
    var license: String
}

struct ParseMeasurement {
    var parserID: String
    var seed: Seed
    var bytes: Int
    var seconds: TimeInterval?
    var documents: Int?
    var iterations: Int
    var success: Bool
    var error: String?

    var megabytesPerSecond: Double? {
        guard let seconds, seconds > 0 else {
            return nil
        }
        return Double(bytes * iterations) / seconds / 1_000_000
    }
}

struct StreamMeasurement {
    var parserID: String
    var documentCount: Int
    var bytes: Int
    var iterations: Int
    var seconds: TimeInterval?
    var parsedDocuments: Int?
    var success: Bool
    var error: String?

    var documentsPerSecond: Double? {
        guard let seconds, seconds > 0 else {
            return nil
        }
        return Double(documentCount * iterations) / seconds
    }
}

struct Score {
    var parser: ParserDefinition
    var parse: Double
    var stream: Double
    var correctness: Double
    var diagnostics: Double
    var packaging: Double

    var overall: Double {
        parse * 0.45
            + stream * 0.20
            + correctness * 0.20
            + diagnostics * 0.10
            + packaging * 0.05
    }
}

struct Timed<Value> {
    var seconds: TimeInterval
    var value: Value
}

let parsers = [
    ParserDefinition(
        id: "pureyaml",
        name: "PureYAML",
        packagingScore: 1000,
        diagnosticScore: 1000,
    ),
    ParserDefinition(
        id: "yams",
        name: "Yams",
        packagingScore: 400,
        diagnosticScore: 0,
    ),
    ParserDefinition(
        id: "swift-yaml",
        name: "swift-yaml",
        packagingScore: 800,
        diagnosticScore: 500,
    ),
]

let configuration = try Configuration(arguments: CommandLine.arguments)
let manifestURL = configuration.fixtureURL.appendingPathComponent("real-yaml-corpus.yaml")
let seedRootURL = configuration.fixtureURL
let seeds = try loadSeeds(from: manifestURL)
let selectedSeeds = selectSeeds(seeds, limit: configuration.limit)
let streamYAML = generatedStream(documentCount: 300)

try FileManager.default.createDirectory(
    at: configuration.artifactURL,
    withIntermediateDirectories: true,
)

print("Swift YAML Geekbench")
print("Fixtures: \(selectedSeeds.count) real-world YAML files")
print("Artifact dir: \(configuration.artifactURL.path)")

var parseMeasurements: [ParseMeasurement] = []
for seed in selectedSeeds {
    let yaml = try String(contentsOf: seedRootURL.appendingPathComponent(seed.localPath), encoding: .utf8)
    let iterations = iterationCount(forBytes: yaml.utf8.count)
    for parser in parsers {
        parseMeasurements.append(measureParse(
            parser: parser,
            seed: seed,
            yaml: yaml,
            iterations: iterations,
        ))
    }
}

var streamMeasurements: [StreamMeasurement] = []
for parser in parsers {
    streamMeasurements.append(measureStream(
        parser: parser,
        yaml: streamYAML,
        bytes: streamYAML.utf8.count,
        documentCount: 300,
        iterations: 20,
    ))
}

let scores = scoreParsers(
    parsers: parsers,
    seeds: selectedSeeds,
    parseMeasurements: parseMeasurements,
    streamMeasurements: streamMeasurements,
)

let report = reportObject(
    seeds: selectedSeeds,
    parseMeasurements: parseMeasurements,
    streamMeasurements: streamMeasurements,
    scores: scores,
)
let jsonData = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
try jsonData.write(to: configuration.artifactURL.appendingPathComponent("swift-yaml-geekbench.json"))
try markdownReport(
    scores: scores,
    seeds: selectedSeeds,
    parseMeasurements: parseMeasurements,
    streamMeasurements: streamMeasurements,
).write(
    to: configuration.artifactURL.appendingPathComponent("swift-yaml-geekbench.md"),
    atomically: true,
    encoding: .utf8,
)

for score in scores.sorted(by: { $0.overall > $1.overall }) {
    print("\(score.parser.name): \(format(score.overall))")
}

struct Configuration {
    var fixtureURL: URL
    var artifactURL: URL
    var limit: Int?

    init(arguments: [String]) throws {
        var fixturePath = "Fixtures"
        var artifactPath = ".build/geekbench-artifacts"
        var limit: Int?
        var index = 1

        while index < arguments.count {
            switch arguments[index] {
            case "--fixtures":
                index += 1
                fixturePath = try arguments.requiredValue(at: index, for: "--fixtures")
            case "--artifact-dir":
                index += 1
                artifactPath = try arguments.requiredValue(at: index, for: "--artifact-dir")
            case "--limit":
                index += 1
                let value = try arguments.requiredValue(at: index, for: "--limit")
                limit = Int(value)
            case "--help", "-h":
                printUsage()
                Foundation.exit(0)
            default:
                throw BenchmarkFailure("unknown argument \(arguments[index])")
            }
            index += 1
        }

        self.fixtureURL = URL(fileURLWithPath: fixturePath, isDirectory: true)
        self.artifactURL = URL(fileURLWithPath: artifactPath, isDirectory: true)
        self.limit = limit
    }
}

func measureParse(
    parser: ParserDefinition,
    seed: Seed,
    yaml: String,
    iterations: Int,
) -> ParseMeasurement {
    let warmup = parseDocuments(parserID: parser.id, yaml: yaml)
    guard warmup.success else {
        return ParseMeasurement(
            parserID: parser.id,
            seed: seed,
            bytes: yaml.utf8.count,
            seconds: nil,
            documents: nil,
            iterations: iterations,
            success: false,
            error: warmup.error,
        )
    }

    do {
        let timed = try time {
            var documentCount = 0
            for _ in 0 ..< iterations {
                let result = parseDocuments(parserID: parser.id, yaml: yaml)
                guard result.success, let documents = result.documents else {
                    throw BenchmarkFailure(result.error ?? "parse failed")
                }
                documentCount += documents
            }
            return documentCount
        }
        return ParseMeasurement(
            parserID: parser.id,
            seed: seed,
            bytes: yaml.utf8.count,
            seconds: timed.seconds,
            documents: timed.value,
            iterations: iterations,
            success: true,
            error: nil,
        )
    } catch {
        return ParseMeasurement(
            parserID: parser.id,
            seed: seed,
            bytes: yaml.utf8.count,
            seconds: nil,
            documents: nil,
            iterations: iterations,
            success: false,
            error: String(describing: error),
        )
    }
}

func measureStream(
    parser: ParserDefinition,
    yaml: String,
    bytes: Int,
    documentCount: Int,
    iterations: Int,
) -> StreamMeasurement {
    let warmup = parseDocuments(parserID: parser.id, yaml: yaml)
    guard warmup.success, warmup.documents == documentCount else {
        return StreamMeasurement(
            parserID: parser.id,
            documentCount: documentCount,
            bytes: bytes,
            iterations: iterations,
            seconds: nil,
            parsedDocuments: nil,
            success: false,
            error: warmup.error ?? "document count mismatch",
        )
    }

    do {
        let timed = try time {
            var parsedDocuments = 0
            for _ in 0 ..< iterations {
                let result = parseDocuments(parserID: parser.id, yaml: yaml)
                guard result.success, let documents = result.documents else {
                    throw BenchmarkFailure(result.error ?? "stream parse failed")
                }
                parsedDocuments += documents
            }
            return parsedDocuments
        }
        return StreamMeasurement(
            parserID: parser.id,
            documentCount: documentCount,
            bytes: bytes,
            iterations: iterations,
            seconds: timed.seconds,
            parsedDocuments: timed.value,
            success: true,
            error: nil,
        )
    } catch {
        return StreamMeasurement(
            parserID: parser.id,
            documentCount: documentCount,
            bytes: bytes,
            iterations: iterations,
            seconds: nil,
            parsedDocuments: nil,
            success: false,
            error: String(describing: error),
        )
    }
}

func parseDocuments(parserID: String, yaml: String) -> (success: Bool, documents: Int?, error: String?) {
    do {
        switch parserID {
        case "pureyaml":
            return (true, try PureYAML.parseStream(yaml).count, nil)
        case "yams":
            return (true, try Array(Yams.load_all(yaml: yaml)).count, nil)
        case "swift-yaml":
            guard documentStartCount(in: yaml) <= 1 else {
                return (false, nil, "compose(yaml:) does not expose multi-document counts")
            }
            _ = try compose(yaml: yaml)
            return (true, 1, nil)
        default:
            return (false, nil, "unknown parser \(parserID)")
        }
    } catch {
        return (false, nil, String(describing: error))
    }
}

func scoreParsers(
    parsers: [ParserDefinition],
    seeds: [Seed],
    parseMeasurements: [ParseMeasurement],
    streamMeasurements: [StreamMeasurement],
) -> [Score] {
    let expectedDocuments = expectedDocumentsBySeed(parseMeasurements)
    var parseScores: [String: Double] = [:]
    var correctnessScores: [String: Double] = [:]
    var streamScores: [String: Double] = [:]

    for seed in seeds {
        let seedMeasurements = parseMeasurements.filter { $0.seed.id == seed.id }
        let fastest = seedMeasurements.compactMap(\.megabytesPerSecond).max() ?? 0
        for parser in parsers {
            let measurement = seedMeasurements.first { $0.parserID == parser.id }
            if let throughput = measurement?.megabytesPerSecond, fastest > 0 {
                parseScores[parser.id, default: 0] += (throughput / fastest) * 1000
            }
            if measurement?.success == true,
               measurement?.documents == expectedDocuments[seed.id]
            {
                correctnessScores[parser.id, default: 0] += 1
            }
        }
    }

    let fastestStream = streamMeasurements.compactMap(\.documentsPerSecond).max() ?? 0
    for parser in parsers {
        let stream = streamMeasurements.first { $0.parserID == parser.id }
        if let documentsPerSecond = stream?.documentsPerSecond, fastestStream > 0 {
            streamScores[parser.id] = (documentsPerSecond / fastestStream) * 1000
        }
        if stream?.success == true {
            correctnessScores[parser.id, default: 0] += 1
        }
    }

    let correctnessCaseCount = Double(seeds.count + 1)
    return parsers.map { parser in
        Score(
            parser: parser,
            parse: (parseScores[parser.id] ?? 0) / Double(seeds.count),
            stream: streamScores[parser.id] ?? 0,
            correctness: ((correctnessScores[parser.id] ?? 0) / correctnessCaseCount) * 1000,
            diagnostics: parser.diagnosticScore,
            packaging: parser.packagingScore,
        )
    }
}

func expectedDocumentsBySeed(_ measurements: [ParseMeasurement]) -> [String: Int] {
    var expected: [String: Int] = [:]
    for measurement in measurements where measurement.parserID == "pureyaml" {
        expected[measurement.seed.id] = measurement.documents
    }
    return expected
}

func reportObject(
    seeds: [Seed],
    parseMeasurements: [ParseMeasurement],
    streamMeasurements: [StreamMeasurement],
    scores: [Score],
) -> [String: Any] {
    [
        "summary": [
            "suite": "Swift YAML Geekbench",
            "seedCount": seeds.count,
            "weights": [
                "parseThroughput": 0.45,
                "streamDocumentsPerSecond": 0.20,
                "correctnessAgreement": 0.20,
                "diagnosticsAndValidation": 0.10,
                "packagingAndPortability": 0.05,
            ],
            "caveat": "Scores are normalized for this checked real-world YAML corpus, not universal YAML compliance.",
        ],
        "seeds": seeds.map(seedObject),
        "parsers": parsers.map(parserObject),
        "parseMeasurements": parseMeasurements.map(parseMeasurementObject),
        "streamMeasurements": streamMeasurements.map(streamMeasurementObject),
        "scores": scores.map(scoreObject).sorted { first, second in
            (first["overall"] as? Double ?? 0) > (second["overall"] as? Double ?? 0)
        },
    ]
}

func markdownReport(
    scores: [Score],
    seeds: [Seed],
    parseMeasurements: [ParseMeasurement],
    streamMeasurements: [StreamMeasurement],
) -> String {
    let categoryCounts = Dictionary(grouping: seeds, by: \.category)
        .mapValues(\.count)
        .sorted { $0.key < $1.key }
    var lines: [String] = []

    lines.append("# Swift YAML Geekbench")
    lines.append("")
    lines.append("Real-world YAML files: \(seeds.count)")
    lines.append("")
    lines.append("> Scores are normalized for this checked real-world YAML corpus, not universal YAML compliance.")
    lines.append("")
    lines.append("## Scores")
    lines.append("")
    lines.append("| Parser | Overall | Parse | Stream | Correctness | Diagnostics | Packaging |")
    lines.append("|---|---:|---:|---:|---:|---:|---:|")
    for score in scores.sorted(by: { $0.overall > $1.overall }) {
        lines.append("| \(score.parser.name) | \(format(score.overall)) | \(format(score.parse)) | \(format(score.stream)) | \(format(score.correctness)) | \(format(score.diagnostics)) | \(format(score.packaging)) |")
    }

    lines.append("")
    lines.append("## Corpus Mix")
    lines.append("")
    lines.append("| Category | Files |")
    lines.append("|---|---:|")
    for (category, count) in categoryCounts {
        lines.append("| \(category) | \(count) |")
    }

    lines.append("")
    lines.append("## Parse Throughput")
    lines.append("")
    lines.append("| Seed | Category | Size | Parser | MB/s | Iterations | Documents | Status |")
    lines.append("|---|---|---|---|---:|---:|---:|---|")
    for measurement in parseMeasurements.sorted(by: { ($0.seed.id, $0.parserID) < ($1.seed.id, $1.parserID) }) {
        lines.append("| \(measurement.seed.id) | \(measurement.seed.category) | \(measurement.seed.size) | \(measurement.parserID) | \(format(measurement.megabytesPerSecond)) | \(measurement.iterations) | \(measurement.documents.map(String.init) ?? "-") | \(measurement.success ? "ok" : "failed") |")
    }

    lines.append("")
    lines.append("## Stream Throughput")
    lines.append("")
    lines.append("| Parser | Documents/sec | Seconds | Parsed documents | Status |")
    lines.append("|---|---:|---:|---:|---|")
    for measurement in streamMeasurements.sorted(by: { $0.parserID < $1.parserID }) {
        lines.append("| \(measurement.parserID) | \(format(measurement.documentsPerSecond)) | \(format(measurement.seconds)) | \(measurement.parsedDocuments.map(String.init) ?? "-") | \(measurement.success ? "ok" : "failed") |")
    }

    lines.append("")
    lines.append("## Weights")
    lines.append("")
    lines.append("- Parse throughput: 45%")
    lines.append("- Stream documents/sec: 20%")
    lines.append("- Correctness agreement: 20%")
    lines.append("- Diagnostics/validation capability: 10%")
    lines.append("- Packaging/portability: 5%")
    lines.append("")
    return lines.joined(separator: "\n")
}

func loadSeeds(from manifestURL: URL) throws -> [Seed] {
    let manifest = try PureYAML.parse(String(contentsOf: manifestURL, encoding: .utf8))
    guard case let .mapping(root) = manifest,
          case let .sequence(seedValues)? = root["seeds"]
    else {
        throw BenchmarkFailure("manifest must contain a seeds sequence")
    }

    return try seedValues.map { value in
        guard case let .mapping(mapping) = value else {
            throw BenchmarkFailure("seed entry must be a mapping")
        }
        return Seed(
            id: try mapping.requiredString("id"),
            localPath: try mapping.requiredString("localPath"),
            category: try mapping.requiredString("category"),
            size: try mapping.requiredString("size"),
            tier: try mapping.requiredString("tier"),
            expectedParse: try mapping.requiredString("expectedParse"),
            byteCount: try mapping.requiredInt("byteCount"),
            lineCount: try mapping.requiredInt("lineCount"),
            repository: try mapping.requiredString("repository"),
            commit: try mapping.requiredString("commit"),
            sourcePath: try mapping.requiredString("sourcePath"),
            license: try mapping.requiredString("license"),
        )
    }
}

func selectSeeds(_ seeds: [Seed], limit: Int?) -> [Seed] {
    guard let limit else {
        return seeds
    }
    return Array(seeds.prefix(limit))
}

func iterationCount(forBytes bytes: Int) -> Int {
    switch bytes {
    case 0 ..< 10_000:
        return 200
    case 10_000 ..< 100_000:
        return 60
    case 100_000 ..< 1_000_000:
        return 10
    case 1_000_000 ..< 5_000_000:
        return 2
    default:
        return 1
    }
}

func generatedStream(documentCount: Int) -> String {
    (0 ..< documentCount).map { index in
        """
        ---
        id: doc-\(index)
        title: Document \(index)
        enabled: \(index.isMultiple(of: 2) ? "true" : "false")
        tags:
          - alpha
          - beta
          - item-\(index)
        nested:
          index: \(index)
          ratio: \(index).25
          empty: ~
        """
    }.joined(separator: "\n")
}

func documentStartCount(in yaml: String) -> Int {
    yaml.split(separator: "\n", omittingEmptySubsequences: false)
        .filter { $0.trimmingCharacters(in: .whitespaces) == "---" }
        .count
}

func time<Value>(_ body: () throws -> Value) rethrows -> Timed<Value> {
    let start = DispatchTime.now().uptimeNanoseconds
    let value = try body()
    let end = DispatchTime.now().uptimeNanoseconds
    return Timed(seconds: Double(end - start) / 1_000_000_000, value: value)
}

func parserObject(_ parser: ParserDefinition) -> [String: Any] {
    [
        "id": parser.id,
        "name": parser.name,
        "packagingScore": parser.packagingScore,
        "diagnosticScore": parser.diagnosticScore,
    ]
}

func seedObject(_ seed: Seed) -> [String: Any] {
    [
        "id": seed.id,
        "localPath": seed.localPath,
        "category": seed.category,
        "size": seed.size,
        "tier": seed.tier,
        "byteCount": seed.byteCount,
        "lineCount": seed.lineCount,
        "repository": seed.repository,
        "commit": seed.commit,
        "sourcePath": seed.sourcePath,
        "license": seed.license,
    ]
}

func parseMeasurementObject(_ measurement: ParseMeasurement) -> [String: Any] {
    [
        "parser": measurement.parserID,
        "seed": measurement.seed.id,
        "category": measurement.seed.category,
        "size": measurement.seed.size,
        "bytes": measurement.bytes,
        "iterations": measurement.iterations,
        "seconds": measurement.seconds as Any,
        "megabytesPerSecond": measurement.megabytesPerSecond as Any,
        "documents": measurement.documents as Any,
        "success": measurement.success,
        "error": measurement.error as Any,
    ]
}

func streamMeasurementObject(_ measurement: StreamMeasurement) -> [String: Any] {
    [
        "parser": measurement.parserID,
        "documentCount": measurement.documentCount,
        "bytes": measurement.bytes,
        "iterations": measurement.iterations,
        "seconds": measurement.seconds as Any,
        "documentsPerSecond": measurement.documentsPerSecond as Any,
        "parsedDocuments": measurement.parsedDocuments as Any,
        "success": measurement.success,
        "error": measurement.error as Any,
    ]
}

func scoreObject(_ score: Score) -> [String: Any] {
    [
        "parser": score.parser.id,
        "name": score.parser.name,
        "overall": score.overall,
        "parse": score.parse,
        "stream": score.stream,
        "correctness": score.correctness,
        "diagnostics": score.diagnostics,
        "packaging": score.packaging,
    ]
}

func format(_ value: Double?) -> String {
    guard let value else {
        return "-"
    }
    return String(format: "%.2f", value)
}

func printUsage() {
    print(
        """
        Usage: pureyaml-geekbench [--fixtures Fixtures] [--artifact-dir .build/geekbench-artifacts] [--limit N]

        Runs the Swift YAML Geekbench over the real-world fixture corpus.
        """,
    )
}

struct BenchmarkFailure: Error, CustomStringConvertible {
    var description: String

    init(_ description: String) {
        self.description = description
    }
}

extension Array where Element == String {
    func requiredValue(at index: Int, for option: String) throws -> String {
        guard indices.contains(index) else {
            throw BenchmarkFailure("\(option) requires a value")
        }
        return self[index]
    }
}

extension PureYAML.Model.Mapping {
    func requiredString(_ key: String) throws -> String {
        guard case let .string(value)? = self[key] else {
            throw BenchmarkFailure("seed entry missing string key \(key)")
        }
        return value
    }

    func requiredInt(_ key: String) throws -> Int {
        guard case let .int(value)? = self[key] else {
            throw BenchmarkFailure("seed entry missing int key \(key)")
        }
        return value
    }
}
