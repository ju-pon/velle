## params.nim -- profile, project params, auto-detection, prompting.
## Resolution: CLI flags > project params > profile > auto-detect > prompt (then save).
import std/[os, strutils, tables, times, algorithm]
import std/json
import parsetoml
import util

type Params* = Table[string, string]

## Params saved to the global profile when prompted; everything else goes to
## the project params. TODO: let shards declare this (design doc section 4).
const identityParams* = ["author", "email", "handle", "license"]

proc profilePath*(): string = configDir() / "profile.toml"
proc projectParamsPath*(): string = getCurrentDir() / ".velle" / "params.toml"

proc loadFlat*(path: string): Params =
  if not fileExists(path): return
  let t = loadToml(path)
  if t.kind == TomlValueKind.Table:
    for k, v in t.tableVal:
      if v.kind == TomlValueKind.String: result[k] = v.stringVal

proc saveFlat*(path: string, p: Params) =
  createDir(parentDir(path))
  var keys: seq[string]
  for k in p.keys: keys.add k
  keys.sort()
  var s = ""
  for k in keys: s.add k & " = " & tomlQuote(p[k]) & "\n"
  writeFile(path, s)

proc parseCliParams*(items: seq[string]): Params =
  for it in items:
    let i = it.find('=')
    if i <= 0: fail("bad --param '" & it & "' (expected name=value)")
    result[it[0 ..< i].strip()] = it[i + 1 .. ^1]

# ---- auto-detection -----------------------------------------------------------

proc detectProjectName(): string =
  let cwd = getCurrentDir()
  if fileExists(cwd / "package.json"):
    try:
      let n = json.parseFile(cwd / "package.json"){"name"}.getStr()
      if n.len > 0: return n
    except CatchableError: discard
  if fileExists(cwd / "Cargo.toml"):
    try:
      let n = tomlStr(tomlGet(loadToml(cwd / "Cargo.toml"), "package"), "name")
      if n.len > 0: return n
    except CatchableError: discard
  for f in walkFiles(cwd / "*.cabal"):
    for line in readFile(f).splitLines:
      if line.toLowerAscii.startsWith("name:"):
        let n = line[5 .. ^1].strip()
        if n.len > 0: return n
  lastPathPart(cwd)

proc detect*(name: string): string =
  case name
  of "author": gitConfig("user.name")
  of "email": gitConfig("user.email")
  of "year": $now().year
  of "name": detectProjectName()
  else: ""

proc peekParam*(name: string): string =
  ## Best known value without prompting (used by `velle new` heuristics).
  let proj = loadFlat(projectParamsPath())
  if name in proj: return proj[name]
  let prof = loadFlat(profilePath())
  if name in prof: return prof[name]
  detect(name)

proc promptValue(name: string, allowEmpty = false): string =
  stdout.write "Enter " & name & ": "
  stdout.flushFile
  try: result = stdin.readLine().strip()
  except EOFError: result = ""
  if result.len == 0 and not allowEmpty:
    fail("no value for param '" & name & "' (pass --param " & name & "=...)")

proc resolveParams*(needed: seq[string], cli: Params, o: Options): Params =
  let proj = loadFlat(projectParamsPath())
  let prof = loadFlat(profilePath())
  for n in needed:
    if n in result: continue
    var v = ""
    if n in cli: v = cli[n]
    elif n in proj: v = proj[n]
    elif n in prof: v = prof[n]
    else: v = detect(n)
    if v.len == 0:
      v = promptValue(n)
      if not o.dryRun:
        let path = if n in identityParams: profilePath() else: projectParamsPath()
        var saved = loadFlat(path)
        saved[n] = v
        saveFlat(path, saved)
        o.vlog "saved " & n & " to " & path
    result[n] = v

proc initProject*(o: Options) =
  ## Creates .velle/params.toml; prompts only for what can't be detected.
  var p = loadFlat(projectParamsPath())
  for n in ["name", "year"]:
    if n notin p:
      var v = detect(n)
      if v.len == 0: v = promptValue(n)
      p[n] = v
  if "description" notin p:
    p["description"] = promptValue("description (optional)", allowEmpty = true)
  if o.dryRun:
    echo "dry run: would write ", projectParamsPath()
  else:
    saveFlat(projectParamsPath(), p)
    echo "wrote ", projectParamsPath()

