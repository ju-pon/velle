## shard.nim -- shard.toml parsing, lookup across sources, dependency resolution.
import std/[os, strutils, sets]
import parsetoml
import util, remote, params

type
  InsertMode* = enum imCreate, imAppend, imRegion
  
  
  ShardFile* = object
    src*, dest*: string
    mode*: InsertMode
    comment*: string   ## comment prefix override for region markers
    region*: string    ## region id; defaults to the shard name

  Shard* = object
    name*, description*, root*, source*: string
    params*, fresh*, requires*: seq[string]
    paramMeta*: seq[ParamInfo]  ## detailed parameter metadata
    files*: seq[ShardFile]
    runs*: seq[string]   ## [[run]] cmd = "..." (never executed without confirmation)

  Source* = object
    label*, dir*: string

proc parseMode(s, shard: string): InsertMode =
  case s
  of "create": result = imCreate
  of "append": result = imAppend
  of "region": result = imRegion
  else: fail("shard " & shard & ": unknown mode '" & s & "'")

proc loadShard*(dir, source, relName: string): Shard =
  let t = loadToml(dir / "shard.toml")
  result.root = dir
  result.source = source
  result.name = tomlStr(t, "name", relName)
  result.description = tomlStr(t, "description")
  result.params = tomlSeq(t, "params")
  result.fresh = tomlSeq(t, "fresh")
  result.requires = tomlSeq(t, "requires")
  ## Accept `require` as a shorthand for the documented `requires` key.
  ## This supports bundle shards that contain no [[file]] entries.
  for r in tomlSeq(t, "require"):
    if r notin result.requires: result.requires.add r
  for ft in tomlTables(t, "file"):
    var f = ShardFile(src: tomlStr(ft, "src"), dest: tomlStr(ft, "dest"),
                      comment: tomlStr(ft, "comment"), region: tomlStr(ft, "region"))
    if f.src.len == 0 or f.dest.len == 0:
      fail("shard " & result.name & ": [[file]] needs src and dest")
    f.mode = parseMode(tomlStr(ft, "mode", "create"), result.name)
    result.files.add f
  for rt in tomlTables(t, "run"):
    let c = tomlStr(rt, "cmd")
    if c.len > 0: result.runs.add c
  
  # Parse [param.name] sections for parameter metadata
  if t.kind == TomlValueKind.Table and t.tableVal.hasKey("param"):
    let paramTable = t.tableVal["param"]
    if paramTable.kind == TomlValueKind.Table:
      for paramName, paramValue in paramTable.tableVal:
        if paramValue.kind == TomlValueKind.Table:
          var meta = ParamInfo(name: paramName)
          
          # Parse scope
          let scopeStr = tomlStr(paramValue, "scope", "project")
          case scopeStr
          of "profile": meta.scope = psProfile
          of "project": meta.scope = psProject
          else: fail("shard " & result.name & ": param " & paramName & " has invalid scope '" & scopeStr & "' (expected 'profile' or 'project')")
          
          meta.prompt = tomlStr(paramValue, "prompt")
          meta.default = tomlStr(paramValue, "default")
          result.paramMeta.add meta

# ---- sources ----------------------------------------------------------------

proc localSources*(): seq[Source] =
  @[Source(label: "project", dir: getCurrentDir() / ".velle" / "shards"),
    Source(label: "user", dir: configDir() / "shards")]

proc remoteSource*(r: Remote): Source =
  Source(label: "remote:" & r.name, dir: remoteDir(r))

proc scanSource*(src: Source): seq[Shard] =
  ## Any directory containing shard.toml is a shard, at any depth.
  if not dirExists(src.dir): return
  for p in walkDirRec(src.dir):
    if p.extractFilename != "shard.toml": continue
    if "/.git/" in p.replace('\\', '/'): continue
    let d = parentDir(p)
    result.add loadShard(d, src.label, relativePath(d, src.dir).replace('\\', '/'))

proc findShard*(name: string): Shard =
  ## project > user > remotes (in configured order). Local shadows remote.
  ## Remotes are only touched (and cloned on first use) if nothing local matches.
  for src in localSources():
    for s in scanSource(src):
      if s.name == name: return s
  for r in loadRemotes():
    try: ensureCloned(r)
    except VelleError as e:
      stderr.writeLine "warning: " & e.msg
      continue
    for s in scanSource(remoteSource(r)):
      if s.name == name: return s
  fail("shard not found: " & name)

proc allShards*(): seq[Shard] =
  for src in localSources(): result.add scanSource(src)
  for r in loadRemotes():
    try: ensureCloned(r)
    except VelleError as e:
      stderr.writeLine "warning: " & e.msg
      continue
    result.add scanSource(remoteSource(r))

# ---- dependencies -------------------------------------------------------------

proc resolveWithRequires*(name: string): seq[Shard] =
  ## Topologically sorted (dependencies first); cycles are an error.
  ## TODO (open question 2): currently resolves requires across all sources.
  var order: seq[Shard]
  var visiting, done: HashSet[string]
  proc visit(n: string) =
    if n in done: return
    if n in visiting: fail("dependency cycle involving " & n)
    visiting.incl n
    let s = findShard(n)
    for r in s.requires: visit(r)
    visiting.excl n
    done.incl n
    order.add s
  visit(name)
  order

