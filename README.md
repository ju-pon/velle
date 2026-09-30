# Velle (skeleton)

Injects parameterized "shards" (licences, gitignores, CI files, justfile targets) into a project.

## Build & test

    nimble install cligen parsetoml
    nimble build
    nimble test

## Try it

    mkdir /tmp/demo && cd /tmp/demo && git init
    mkdir -p .velle/shards && cp -r /path/to/velle/examples/license-mit .velle/shards/
    velle init
    velle add license/mit --dry-run

## Layout

    src/velle.nim     entry point + cligen dispatch
    src/cli.nim       command procs (add flow lives in doAdd)
    src/params.nim    profile, project params, detection, prompting
    src/shard.nim     shard.toml parsing, lookup, dependency resolution
    src/render.nim    {{param}} substitution (template.nim is a keyword clash)
    src/apply.nim     create/append/region planning + atomic apply
    src/diff.nim      git diff --no-index with built-in fallback
    src/remote.nim    remote config, clone/fetch, cache
    src/newshard.nim  `velle new` + param extraction heuristic
    src/util.nim      errors, line endings, process + TOML helpers

## Known gaps / TODO

- `--ref` is `--pin` for now (cligen can't name a param `ref`).
- Which params are identity vs project is hardcoded (`identityParams`), not shard-declared.
- Apply rollback if a rename fails midway; file mode preservation.
- Block-comment syntax for regions in md/html.
- Official remote URL is a placeholder.
- Windows untested.

