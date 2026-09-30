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

## Getting started

There are binaries available as artefacts of CI builds.

### Manual Install

Install the dependencies and build Velle:

```
nimble install cligen parsetoml
nimble build
```

### Starting Coding

Create a project and add a local shard:

```
mkdir my-project
cd my-project
git init

velle add path/to/shard --dry-run
```

The `--dry-run` option shows the changes without writing anything. When the
preview looks right, run the command again without `--dry-run` and confirm the
changes.

If you do not know the shard name, leave it out:

```
velle add
```

Velle will open `fzf` if it is installed. Without `fzf`, it provides a simple
search and selection prompt using `rg`.

## How shards work

A shard is a directory containing a `shard.toml` file and, for file-producing
shards, a `files` directory. Here is a small example:

```
my-shard/
├── shard.toml
└── files/
    └── .gitignore
```

The corresponding `shard.toml` might look like this:

```
name        = "gitignore/base"
description = "Common files to ignore"
params      = []

[[file]]
src  = "files/.gitignore"
dest = ".gitignore"
mode = "create"
```

Templates can refer to parameters with `{{name}}` syntax:

```
name   = "license/header"
params = ["author", "year"]

[[file]]
src  = "files/header.txt"
dest = "LICENSE"
mode = "create"
```

A shard can create a file, append a block to an existing file, or maintain a
named region. The available modes are `create`, `append`, and `region`.

### Dependency bundles

A shard does not need to contain any files. It can simply collect other shards
into a convenient bundle:

```
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

Both `require = [...]` and `requires = [...]` are accepted. Dependencies are
resolved first and applied in dependency order.

## Checking shards

Before using a shard, you can validate it with:

```
velle check path/to/shard
```

If the path is a directory containing multiple shards, all nested `shard.toml`
files are checked:

```
velle check .velle/shards
```

Validation checks that:

- every `{{parameter}}` used by a template is declared in `params`;

- declared parameters are not accidentally unused;

- template markers are well formed; and

- every template file listed by the shard exists.

`velle add` performs the same validation for the selected shard and its
dependencies before asking for parameter values or planning changes.

## Useful commands

| Command | Purpose |
| --- | --- |
| `velle init` | Create project parameter storage. |
| `velle add <shard>` | Apply a shard and its dependencies. |
| `velle add` | Select a shard interactively. |
| `velle check [path]` | Validate one shard or a directory of shards. |
| `velle search <term>` | Search available shard names and descriptions. |
| `velle new <name> [files...]` | Create a shard from existing files. |
| `velle remote list` | List configured shard remotes. |
| `velle remote refresh` | Refresh configured remotes. |

Use `velle <command> --help` for command-specific options.

## Development

To build the project:

```
nimble build
```

The test command and CI setup are still being completed as part of the WIP
stabilization work.
