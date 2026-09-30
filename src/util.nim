## util.nim -- errors, paths, line endings, process helpers, TOML helpers.
import std/[os, osproc, strutils]
import parsetoml

type
  VelleError* = object of CatchableError

  Options* = object
    yes*, dryRun*, verbose*, keep*, allowRun*: bool

  LineEnding* = enum leLF, leCRLF

proc fail*(msg: string) {.noreturn.} =
  raise newException(VelleError, msg)

proc vlog*(o: Options, msg: string) =
  if o.verbose: stderr.writeLine msg

# ---- line endings -----------------------------------------------------------

proc detectLineEnding*(s: string): LineEnding =
  if "\r\n" in s: leCRLF else: leLF

proc toLF*(s: string): string = s.replace("\r\n", "\n")

proc withLineEnding*(s: string, le: LineEnding): string =
  let lf = toLF(s)
  if le == leCRLF: lf.replace("\n", "\r\n") else: lf

# ---- paths ------------------------------------------------------------------

proc configDir*(): string = getConfigDir() / "velle"
proc cacheDir*(): string = getCacheDir() / "velle"

# ---- processes --------------------------------------------------------------

proc git*(args: openArray[string], dir = ""): tuple[output: string, exitCode: int] =
  var cmd = "git"
  for a in args: cmd.add " " & quoteShell(a)
  execCmdEx(cmd, workingDir = dir)

proc gitConfig*(key: string): string =
  let (o, c) = git(["config", "--get", key])
  if c == 0: o.strip() else: ""

proc dirtyPaths*(paths: seq[string]): seq[string] =
  ## Paths among `paths` with uncommitted changes (empty if not a git repo).
  if paths.len == 0: return
  var args = @["status", "--porcelain", "--"]
  args.add paths
  let (o, c) = git(args)
  if c != 0: return
  for l in o.splitLines:
    if l.len > 3: result.add l[3 .. ^1]

proc confirm*(question: string, o: Options): bool =
  if o.yes: return true
  stdout.write question & " [y/N] "
  stdout.flushFile
  var a = ""
  try: a = stdin.readLine().strip().toLowerAscii()
  except EOFError: discard
  a in ["y", "yes"]

# ---- TOML helpers (parsetoml's raw API is a bit low-level) -------------------

proc loadToml*(path: string): TomlValueRef =
  try: parsetoml.parseFile(path)
  except CatchableError as e: fail(path & ": " & e.msg)

proc tomlGet*(t: TomlValueRef, key: string): TomlValueRef =
  if t != nil and t.kind == TomlValueKind.Table and t.tableVal.hasKey(key):
    t.tableVal[key]
  else: nil

proc tomlStr*(t: TomlValueRef, key: string, default = ""): string =
  let v = tomlGet(t, key)
  if v != nil and v.kind == TomlValueKind.String: v.stringVal else: default

proc tomlSeq*(t: TomlValueRef, key: string): seq[string] =
  let v = tomlGet(t, key)
  if v != nil and v.kind == TomlValueKind.Array:
    for e in v.arrayVal:
      if e.kind == TomlValueKind.String: result.add e.stringVal

proc tomlTables*(t: TomlValueRef, key: string): seq[TomlValueRef] =
  ## Array-of-tables, e.g. [[file]]
  let v = tomlGet(t, key)
  if v != nil and v.kind == TomlValueKind.Array:
    for e in v.arrayVal:
      if e.kind == TomlValueKind.Table: result.add e

proc tomlQuote*(s: string): string =
  "\"" & s.replace("\\", "\\\\").replace("\"", "\\\"") & "\""

