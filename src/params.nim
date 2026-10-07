## params.nim -- profile, project params, auto-detection, prompting.
## Resolution: CLI flags > project params > profile > auto-detect > prompt (then save).
import std/[os, strutils, tables, times, algorithm, random]
import std/json
import parsetoml
import util, render

type 
  Params* = Table[string, string]
  
  ParamScope* = enum psProfile, psProject
  
  ParamInfo* = object
    name*: string
    scope*: ParamScope
    prompt*: string
    default*: string

## Legacy profile parameters for backward compatibility.
## New shards should use [param.name] scope declarations instead.
const identityParams* = ["author", "email", "handle", "license"]

## Built-in fresh values that are available by default.
## Shards can declare their own fresh values in addition to these.
const builtinFreshNames* = ["timestamp", "current_year", "current_date", "git_branch", "git_commit", "random_id"]

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

proc detectFresh*(name: string): string =
  ## Generate fresh values that are computed each time and never cached.
  case name
  of "timestamp": $getTime().toUnix()
  of "current_year": $now().year
  of "current_date": now().format("yyyy-MM-dd")
  of "git_branch":
    let branch = gitConfig("symbolic-ref --short HEAD")
    if branch.len > 0: branch else: "main"
  of "git_commit":
    let commit = gitConfig("rev-parse HEAD")
    if commit.len > 0: commit[0..6] else: "unknown"
  of "random_id": $(rand(899999) + 100000)  # 6-digit random number
  else: ""

proc detect*(name: string): string =
  ## Detect cacheable parameters.
  if name in builtinFreshNames:
    return detectFresh(name)
  case name
  of "author": gitConfig("user.name")
  of "email": gitConfig("user.email")
  of "year": $now().year  # Keep for backward compatibility, but consider using current_year
  of "name": detectProjectName()
  of "project": detectProjectName()
  else: ""

proc peekParam*(name: string): string =
  ## Best known value without prompting (used by `velle new` heuristics).
  if name in builtinFreshNames:
    return detectFresh(name)
  let proj = loadFlat(projectParamsPath())
  if name in proj: return proj[name]
  let prof = loadFlat(profilePath())
  if name in prof: return prof[name]
  detect(name)

proc promptValue(name: string, prompt = "", allowEmpty = true): string =
  let promptText = if prompt.len > 0: prompt else: "Enter " & name
  stdout.write promptText & ": "
  stdout.flushFile
  try: result = stdin.readLine().strip()
  except EOFError: result = ""
  if result.len == 0 and not allowEmpty:
    fail("no value for param '" & name & "' (pass --param " & name & "=...)")

proc resolveParamsWithMeta*(needed: seq[string], freshNames: seq[string], paramMeta: seq[ParamInfo], cli: Params, o: Options): Params =
  let proj = loadFlat(projectParamsPath())
  let prof = loadFlat(profilePath())
  
  # Build lookup table for parameter metadata
  var metaMap: Table[string, ParamInfo]
  for meta in paramMeta:
    metaMap[meta.name] = meta
  
  for n in needed:
    if n in result: continue
    var v = ""
    
    # Handle fresh values - always compute fresh, never cache
    if n in freshNames or n in builtinFreshNames:
      if n in cli: v = cli[n]  # CLI override still works
      else: v = detectFresh(n)
      result[n] = v
      continue
    
    # Check if we have metadata for this parameter
    let hasMeta = n in metaMap
    let meta = if hasMeta: metaMap[n] else: ParamInfo(name: n, scope: psProject)
    
    # Handle regular cached parameters with metadata support
    if n in cli: v = cli[n]
    elif n in proj: v = proj[n]
    elif n in prof: v = prof[n]
    else: 
      # Try default value template if provided
      if hasMeta and meta.default.len > 0:
        v = render(meta.default, result, "param default")
      else:
        v = detect(n)
    
    if v.len == 0:
      let customPrompt = if hasMeta and meta.prompt.len > 0: meta.prompt else: ""
      v = promptValue(n, customPrompt)
      if not o.dryRun:
        # Use shard-declared scope or fallback to legacy logic
        let useProfile = if hasMeta: (meta.scope == psProfile) else: (n in identityParams)
        let path = if useProfile: profilePath() else: projectParamsPath()
        var saved = loadFlat(path)
        saved[n] = v
        saveFlat(path, saved)
        o.vlog "saved " & n & " to " & path
    result[n] = v

proc resolveParams*(needed: seq[string], freshNames: seq[string], cli: Params, o: Options): Params =
  resolveParamsWithMeta(needed, freshNames, @[], cli, o)

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

