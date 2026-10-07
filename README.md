# Velle

Velle helps you add small, reusable pieces of project configuration without
copying and editing them by hand.

A reusable piece is called a **shard**. A shard might provide a license file, a
`.gitignore` fragment, a CI workflow, or a target in a `justfile`. Shards can
accept parameters and can depend on other shards, so a larger setup can be
assembled from smaller pieces.

Velle is a work in progress. The basic `add` workflow is usable, but the file
rollback guarantees, parameter configuration, and some cross-platform behavior
are still being developed.

## Installation

Download precompiled binaries from CI build artifacts, or build from source:

```
nimble install cligen parsetoml
nimble build
```

## Quick start

Initialize a project and add a shard:

```
mkdir my-project
cd my-project
git init
velle init

velle add path/to/shard --dry-run
velle add path/to/shard
```

Use `--dry-run` to preview changes. Use `velle add` without arguments for interactive shard selection (requires `fzf` or `rg`).

## Shards

A shard is a directory containing `shard.toml` and optionally a `files/` directory.

### Basic shard structure

```
my-shard/
├── shard.toml
└── files/
    └── .gitignore
```

### shard.toml format

```toml
name        = "gitignore/base"
description = "Common files to ignore"
params      = ["author", "project"]
fresh       = ["timestamp", "random_id"]
requires    = ["other/shard"]

[[file]]
src     = "files/.gitignore"
dest    = ".gitignore"
mode    = "create"
comment = "#"      # override comment prefix for regions
region  = "custom" # override region name

[[run]]
cmd = "chmod +x script.sh"
```

### Parameters

Templates use `{{parameter}}` syntax. Parameters are resolved in this order:

1. CLI flags (`--param name=value`)
2. Project parameters (`.velle/params.toml`)
3. Profile parameters (`~/.config/velle/profile.toml`)
4. Auto-detection (git config, project files)
5. Interactive prompts

**Fresh parameters** are computed each time and never cached:
- Built-in: `timestamp`, `current_year`, `current_date`, `git_branch`, `git_commit`, `random_id`
- Shard-defined: add names to `fresh = [...]` array

### File modes

- `create` - Write new file (default)
- `append` - Add content to end of existing file
- `region` - Maintain named section between markers

### Dependency bundles

Bundle shards collect dependencies without files:

```toml
name        = "dev/gitignore-bundle-full"
description = "A complete gitignore setup"
params      = []
require     = [
  "dev/gitignore-base",
  "dev/gitignore-node",
  "dev/gitignore-python",
  "dev/gitignore-build",
  "dev/gitignore-test",
  "dev/gitignore-logs",
  "dev/gitignore-secrets",
  "dev/gitignore-ide",
]
```

Both `require` and `requires` are accepted. Dependencies resolve recursively in topological order.

## Validation

Validate shards before use:

```
velle check path/to/shard
velle check .velle/shards  # check directory of shards
```

Validation verifies:
- Template parameters are declared in `params`
- Declared parameters are used
- Template markers are well-formed
- Source files exist

`velle add` validates automatically before prompting for parameters.

## Commands

| Command | Description |
| --- | --- |
| `velle init` | Initialize project parameter storage |
| `velle add <shard>` | Apply shard and dependencies |
| `velle add` | Interactive shard selection |
| `velle check [path]` | Validate shard or directory |
| `velle search <term>` | Search shard names and descriptions |
| `velle new <name> [files...]` | Create shard from existing files |
| `velle remote list` | List configured remotes |
| `velle remote refresh` | Update remote repositories |

Global options: `--dry-run`, `--yes`, `--verbose`

## Development

```bash
nimble build
nimble test
```
