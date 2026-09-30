# Velle: Remaining Work (Design Doc v1.1)

Status: **WIP**. The core `add` flow, dependency bundles, parameter rendering,
interactive shard selection, and initial validation are implemented. This
document covers what remains to reach the v1 described in the original design
doc. Section numbers like "§5" refer to that document.

## 1. Where we are

Working (still being hardened):

- `init`, `add`, `new`, `remote`, `search` command procs

- `check` command and pre-add shard validation

- `create` / `append` / `region` planning, diff, confirm, staged apply

- Param resolution chain, `{{param}}` rendering, dependency ordering

- Empty dependency-only shards using `require` or `requires`

- Interactive `add` selection with fzf or an rg fallback

- Unit and golden tests (written, not yet all run)

Not yet complete: atomic rollback, remote coverage, parameter scopes, and the
remaining authoring and release work.

## 2. Phases

| Phase | Goal | Exit criteria |
| --- | --- | --- |
| 0 | Stabilise (deferred) | `nimble build` and `nimble test` green on Linux and macOS in CI |
| 1 | Close spec gaps | Every §5-§10 behaviour implemented or explicitly deferred |
| 2 | Harden | Failure, remote and CRLF tests pass; atomicity verified |
| 3 | Ship | Release binaries, shard authoring guide, seed shards |

## 3. Phase 0: Stabilise (deferred)

Phase 0 is intentionally deferred while feature work continues. Its tasks
remain listed because they are still required before a release.

**T0.1 Compile and test cleanly.** Fix remaining compiler errors (parsetoml/cligen API details are the likely spots). Done when `nimble test` passes locally.

**T0.2 CI.** GitHub Actions: Linux and macOS, `nimble build`, `nimble test`, Nim 2.0.x and latest stable. Cache `~/.nimble`.

**T0.3 End-to-end smoke script.** `tests/smoke.sh`: temp dir, `git init`, copy example shard, run `velle init`, `add --yes`, `add --yes` again (idempotence), assert file contents. Catches wiring bugs the unit tests cannot.

## 4. Phase 1: Close the spec gaps

### T1.1 Shard validation (`velle check`) — done

Design:

- On shard load, scan every template for `{{name}}` and compare with `params`.

- Undeclared use: error naming shard, file, param. Declared but unused: warning.

- Expose as `velle check [path]` for shard authors (runs on a directory, no project needed).

- `velle add` runs the same check before prompting anything.

Implemented: `velle check [path]` validates templates and source files,
reports undeclared parameters as errors, warns about unused declarations, and
`velle add` runs the validation before prompting.

### T1.2 Shard-declared param scope and prompts (§4)

Currently `identityParams` is hardcoded. Keep `params = [...]` working and add an optional table:

```
params = ["author", "project"]

[param.author]
scope  = "profile"       # profile | project
prompt = "Your full name"

[param.project]
scope   = "project"
default = "{{name}}"     # optional; may reference other params
```

Rules: unknown scope is a load error; a shard-declared scope overrides the built-in default; `default` is used for detection fallback before prompting.

### T1.4 Global flags (§10)

`--yes`, `--dry-run`, `--verbose` are per-command today. Move to cligen multi-command shared options (a shared param set in `dispatchMulti`) so `velle --dry-run add x` also works, or document that flags follow the subcommand. Decide, then test both.

### T1.5 `velle new --dry-run` and `--yes`

`cmdNew` accepts `--dry-run` but `newShard` ignores it and always writes. Honour it: print what would be created and which replacements would be offered.

### T1.6 Block-comment regions

Markdown and HTML have no line comments. Extend the comment table to `(open, close)` pairs, e.g. `<!-- >>> velle:x >>> -->`. Shard `comment = "<!--|-->"` override syntax. Golden tests for `.md` and `.html`.

### T1.7 Lookup performance and clarity

`findShard` parses every `shard.toml` on every call. Fine for tens of shards, poor for large remotes.

- Build a lazy name→dir index per source, cached in memory per run.

- `velle add` should say when a local shard shadowed a remote of the same name.

- Reject two shards with the same name inside one source (error, list both paths).

### T1.8 Decide the open questions (§14)

Recommended defaults, to be confirmed:

| Question | Recommendation |
| --- | --- |
| Regions in v1? | Yes. Already built; test coverage is the real cost. |
| `requires` across remotes? | Yes, resolved through normal lookup order. Document that a local shadow changes the graph. |
| `[[run]]` in v1? | Keep, behind confirmation as built. It is already gated; removing it later is a breaking change, adding it later is not. Revisit if governance of the official remote is unresolved. |

## 5. Phase 2: Harden

### T2.1 Atomic apply, properly (§8)

Today: stage temp files, then rename in a loop. If a rename fails midway, earlier files are already replaced.

Design:

1. Stage all temp files (as now).

1. Before renaming, move each existing target aside to `<path>.velle-bak`.

1. Rename temps into place.

1. On any failure: rename backups back, delete new files created, delete temps.

1. On success: delete backups.
Also preserve file mode (`getFilePermissions` / `setFilePermissions`) and refuse to write through symlinks that leave the project.

Test: inject a failure on the Nth rename (test-only hook, e.g. a read-only directory) and assert the tree is byte-identical to before.

### T2.2 Failure test suite (§12)

- Missing param, malformed markers (already unit-tested), dependency cycle, duplicate shard names

- Write failure mid-apply (T2.1)

- `dest` escaping the project (`../x`, absolute path)

- Empty file, file with only a trailing newline, file without trailing newline, CRLF files, mixed line endings

### T2.3 Remote tests without network

Local bare repo fixture created in the test: `git init --bare`, push a shard tree. Cover: first clone, cached second use (offline), `refresh` picks up a new commit, pinned tag stays put after upstream moves, removing a remote deletes its cache, unreachable remote produces a warning and lookup continues.

Offline behaviour to define: if the cache is missing and the network is down, `add` prints one warning per remote, not one per lookup.

### T2.4 `velle new` heuristics

Risks: replacing a short or common value (a project named `app`) corrupts unrelated text. Mitigations: whole-word matching for `name`, show each match with line context in the prompt, skip values shorter than 3 characters unless forced. Tests with tricky input.

### T2.5 Dirty-tree warning

Currently compares against paths relative to cwd. Verify from subdirectories and inside worktrees; if not a git repo, say so once and continue.

### T2.6 Idempotence audit

Property-style test: for every golden case and every mode, `add` twice equals `add` once. Also `add` after a user hand-edits inside a region: the diff must show their edit being overwritten so the confirm step is meaningful.

## 6. Phase 3: Ship

**T3.1 Release binaries.** Static builds for Linux (x86_64, arm64, via musl), macOS (x86_64, arm64), triggered by a version tag. Attach checksums. Add `--version`.

**T3.2 Shard authoring guide.** One page: directory layout, `shard.toml` reference (all keys, modes, region ids, comment override, `[[run]]`), template syntax and escaping, using `velle check`, publishing via a remote.

**T3.3 Seed shards.** Enough for the official remote to be useful on day one: `license/{mit,bsd-3,apache-2.0}`, `gitignore/{base,nim,haskell,rust,node}`, `readme/basic`, `just/{lint,test}`, `ci/github-actions-{nim,haskell}`. Each with a golden test.

**T3.4 User documentation.** README quickstart, param resolution order with an example, undo with git, how shadowing works.

## 7. Risks

| Risk | Mitigation |
| --- | --- |
| parsetoml API drift or gaps | All access goes through the small helpers in `util.nim`; swap the backend in one place |
| Region patching edge cases (hand-edited blocks, odd markers) | Abort-on-ambiguity policy, exhaustive golden tests, no partial writes |
| `[[run]]` misuse from third-party remotes | Always printed, separate confirmation, never auto-run under `--yes` alone |
| Cross-platform path and line-ending bugs | CI on Linux and macOS from Phase 0; Windows tracked separately |

## 8. Suggested order

1. T1.2 (shard-declared parameter scopes and prompts)

1. T2.1 and T2.2 (atomicity and failure safety)

1. T1.5, T1.6, T1.4, T1.7

1. T2.3-T2.6

1. Phase 3

1. Resolve T1.8 open questions before T3.1

Estimate: roughly 2 weeks part-time, dominated by T2.1-T2.3.
