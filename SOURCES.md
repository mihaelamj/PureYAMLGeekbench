# Fixture Sources

`Fixtures/real-yaml-corpus.yaml` is the authoritative provenance manifest for
this repository.

Every entry records:

- stable fixture ID,
- local fixture path,
- source repository,
- pinned commit,
- upstream source path,
- raw source URL,
- license,
- byte and line counts.

The fixtures are copied from public repositories and retain their upstream
license metadata in the manifest. The benchmark harness code in this repository
is MIT licensed.

Do not add private YAML fixtures to this public repository. Private or
license-unclear material belongs in a private research repository or should be
reduced into an independently written fixture.
