#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

swift run \
  -c release \
  --package-path "$ROOT_DIR" \
  pureyaml-geekbench \
  --fixtures "$ROOT_DIR/Fixtures" \
  --artifact-dir "$ROOT_DIR/.build/geekbench-artifacts" \
  "$@"
