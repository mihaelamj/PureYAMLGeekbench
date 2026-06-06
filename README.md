# PureYAMLGeekbench

Real-world Swift YAML parser benchmarks for PureYAML, Yams, and other Swift
parser candidates.

This repo exists so the main `PureYAML` package can stay small,
dependency-free, and pure Swift while the benchmark suite can carry a large YAML
fixture corpus and external parser dependencies.

## What It Measures

The default run uses 100+ checked real-world YAML files copied from the PureYAML
corpus manifest:

- OpenAPI and Swagger specs
- Kubernetes and CRD documents
- Helm values and chart metadata
- GitHub Actions workflows
- Docker Compose files
- Prometheus configs
- Static-site and application config files

The benchmark also generates a 300-document YAML stream to measure
multi-document parsing.

## Run

```sh
bash scripts/run-geekbench.sh
```

Artifacts are written to:

- `.build/geekbench-artifacts/swift-yaml-geekbench.json`
- `.build/geekbench-artifacts/swift-yaml-geekbench.md`

For a fast smoke run:

```sh
swift run -c release pureyaml-geekbench --limit 10
```

## Scoring

Each performance lane is normalized to the fastest parser in that lane. Fastest
is `1000`; other parsers scale by ratio.

Weights:

- Parse throughput: 45%
- Stream documents/sec: 20%
- Correctness agreement: 20%
- Diagnostics/validation capability: 10%
- Packaging/portability: 5%

The score is for this checked real-world YAML workload. It is not a universal
YAML compliance score.

## Parser Lanes

- `PureYAML`: dependency-free Swift parser, structured diagnostics, structured
  validation, multi-document stream API.
- `Yams`: Swift API over LibYAML, strong baseline parser throughput,
  no PureYAML-style structured validation artifact.
- `swift-yaml`: pure Swift parser candidate. It receives single-document parse
  throughput credit, but no stream-lane credit when its public API does not
  expose comparable multi-document counts.

## Fixture Provenance

The fixture manifest is `Fixtures/real-yaml-corpus.yaml`. It records source
repositories, pinned commits, source paths, byte counts, line counts, and
licenses for every copied YAML file.
