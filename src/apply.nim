## apply.nim -- create/append/region logic, change planning, atomic apply.
## Planning is pure (strings in, strings out); nothing touches disk until applyChanges.
import std/[os, strutils, options, tables]
import util, shard, render, params

type
  Change* = object
    path*: string
    oldText*: Option[string]   ## none = file does not exist yet
    newText*: string
    shard*: string

# ---- comment syntax -----------------------------------------------------------

proc commentFor*(dest, override: string): string =
  ## Built-in table by file extension. TODO: block comments (<!-- --> for md/html).
  if override.len > 0: return override
  let ext = splitFile(dest).ext.toLowerAscii
  case ext
  of ".hs", ".cabal", ".sql", ".lua": "--"
  of ".c", ".h", ".cpp", ".js", ".ts", ".go", ".rs", ".java", ".swift": "//"
  else: "#"   # also justfile, Makefile, .gitignore, yaml, toml, sh, ...

# ---- per-mode planning (LF-normalised text in, LF text out) --------------------

proc appendBlock(lf, rendered: string): string =
  let body = rendered.strip(leading = false, trailing = true, chars = {'\n'})
  if body in lf: return lf                       # idempotent
  result = lf
  if result.len > 0 and not result.endsWith("\n"): result.add "\n"
  result.add body & "\n"

proc regionPatch(lf, rendered, id, comment: string): string =
  let beginM = comment & " >>> velle:" & id & " >>>"
  let endM = comment & " <<< velle:" & id & " <<<"
  let hadNl = lf.endsWith("\n")
  let core = if hadNl: lf[0 ..< lf.len - 1] else: lf
  var lines: seq[string] = if lf.len == 0: @[] else: core.split('\n')
  var bs, es: seq[int]
  for i, l in lines:
    if l.strip() == beginM: bs.add i
    elif l.strip() == endM: es.add i
  if bs.len > 1 or es.len > 1:
    fail("duplicate region markers for '" & id & "'; aborting, nothing written")
  if bs.len != es.len:
    fail("unclosed region marker for '" & id & "'; aborting, nothing written")
  let body = rendered.strip(leading = false, trailing = true, chars = {'\n'}).split('\n')
  if bs.len == 0:
    lines.add beginM
    lines.add body
    lines.add endM
    return lines.join("\n") & "\n"
  if es[0] < bs[0]:
    fail("region end marker before begin for '" & id & "'; aborting, nothing written")
  lines = lines[0 .. bs[0]] & body & lines[es[0] .. ^1]
  lines.join("\n") & (if hadNl: "\n" else: "")

proc planFile*(f: ShardFile, shardName, rendered: string,
               existing: Option[string], keep: bool): string =
  ## New content for one [[file]] entry. Equal to the old content => no change.
  let text = toLF(rendered)
  case f.mode
  of imCreate:
    if existing.isSome and keep: return existing.get
    return text
  of imAppend, imRegion:
    let old = if existing.isSome: existing.get else: ""
    let le = detectLineEnding(old)
    let hadTrailing = old.len == 0 or old.endsWith("\n")
    var lf = toLF(old)
    if f.mode == imAppend:
      lf = appendBlock(lf, text)
    else:
      let id = if f.region.len > 0: f.region else: shardName.replace('/', '-')
      lf = regionPatch(lf, text, id, commentFor(f.dest, f.comment))
    if not hadTrailing and lf.endsWith("\n"): lf.setLen(lf.len - 1)
    return withLineEnding(lf, le)

# ---- whole-shard planning -------------------------------------------------------

proc safeDest(dest: string): string =
  if dest.isAbsolute or ".." in dest.replace('\\', '/').split('/'):
    fail("refusing dest outside the project: " & dest)
  getCurrentDir() / dest

proc planShards*(shards: seq[Shard], params: Params, o: Options): seq[Change] =
  ## Shards are applied in order; later shards see earlier pending edits.
  var byPath = initOrderedTable[string, Change]()
  for s in shards:
    for f in s.files:
      let dest = safeDest(f.dest)
      let rendered = render(readFile(s.root / f.src), params, s.name)
      var ch: Change
      if dest in byPath:
        ch = byPath[dest]
      else:
        ch = Change(path: dest, shard: s.name,
                    oldText: if fileExists(dest): some(readFile(dest)) else: none(string))
      let current = if dest in byPath: some(ch.newText) else: ch.oldText
      ch.newText = planFile(f, s.name, rendered, current, o.keep)
      byPath[dest] = ch
  for ch in byPath.values:
    if ch.oldText.isNone or ch.oldText.get != ch.newText: result.add ch

# ---- atomic apply ---------------------------------------------------------------

proc applyChanges*(changes: seq[Change]) =
  ## Stage everything to temp files first; only then rename into place.
  ## TODO: preserve file modes; roll back if a rename fails midway.
  var staged: seq[(string, string)]
  try:
    for ch in changes:
      createDir(parentDir(ch.path))
      let tmp = ch.path & ".velle-tmp"
      staged.add (tmp, ch.path)
      writeFile(tmp, ch.newText)
  except CatchableError as e:
    for (t, _) in staged: discard tryRemoveFile(t)
    fail("write failed, nothing was changed: " & e.msg)
  for (t, p) in staged: moveFile(t, p)

