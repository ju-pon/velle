## cli.nim -- command procs (cligen wiring lives in velle.nim).
import std/[os, osproc, strutils, sequtils]
import util, params, shard, validate, apply, diff, remote, newshard

proc guarded(body: proc()): int =
  try:
    body()
    result = 0
  except VelleError as e:
    stderr.writeLine "velle: " & e.msg
    result = 1

proc mkOpts(yes, dryRun, verbose: bool, keep = false, allowRun = false): Options =
  Options(yes: yes, dryRun: dryRun, verbose: verbose, keep: keep, allowRun: allowRun)

# ---- add ------------------------------------------------------------------------

proc chooseShard(): string =
  ## Pick a shard when `velle add` is invoked without its final argument.
  ## Prefer fzf; use rg as a searchable fallback when fzf is unavailable.
  var names: seq[string]
  for s in allShards():
    if s.name notin names: names.add s.name
  if names.len == 0: fail("no shards found")

  let listPath = getTempDir() / ("velle-shards-" & $getCurrentProcessId() & ".txt")
  let selectedPath = listPath & ".selected"
  writeFile(listPath, names.join("\n") & "\n")
  defer:
    discard tryRemoveFile(listPath)
    discard tryRemoveFile(selectedPath)

  let fzf = findExe("fzf")
  if fzf.len > 0:
    let code = execCmd(quoteShell(fzf) &
      " --height=40% --reverse --no-multi --prompt='shard> ' < " &
      quoteShell(listPath) & " > " & quoteShell(selectedPath))
    if code == 0 and fileExists(selectedPath): return readFile(selectedPath).strip()
    return ""

  if findExe("rg").len > 0:
    stdout.write "Search shards (empty lists all): "
    stdout.flushFile
    var query = ""
    try: query = stdin.readLine().strip()
    except EOFError: return ""
    let (matchesText, code) = execCmdEx("rg --fixed-strings --line-number --no-heading " &
      "--color never " & quoteShell(query) & " " & quoteShell(listPath))
    if code != 0: return ""
    var matches: seq[string]
    for line in matchesText.splitLines:
      let colon = line.find(':')
      if colon >= 0 and colon + 1 < line.len:
        let name = line[colon + 1 .. ^1].strip()
        if name.len > 0: matches.add name
    if matches.len == 1: return matches[0]
    if matches.len == 0: return ""
    for i, name in matches: echo "[", i + 1, "] ", name
    stdout.write "Select shard (number or name): "
    stdout.flushFile
    var answer = ""
    try: answer = stdin.readLine().strip()
    except EOFError: return ""
    try:
      let n = parseInt(answer)
      if n >= 1 and n <= matches.len: return matches[n - 1]
    except ValueError: discard
    if answer in matches: return answer
    return ""

  for i, name in names: echo "[", i + 1, "] ", name
  stdout.write "Select shard (number or name): "
  stdout.flushFile
  var answer = ""
  try: answer = stdin.readLine().strip()
  except EOFError: return ""
  try:
    let n = parseInt(answer)
    if n >= 1 and n <= names.len: return names[n - 1]
  except ValueError: discard
  if answer in names: answer else: ""

proc doAdd(args, param: seq[string], o: Options) =
  if args.len > 1: fail("usage: velle add [<shard>] [--param k=v]")
  let shardName = if args.len == 1: args[0] else: chooseShard()
  if shardName.len == 0:
    echo "no shard selected"
    return
  # 1. resolve shard + requires
  let shards = resolveWithRequires(shardName)
  let validation = validateShards(shards)
  printReport(validation)
  if validation.errors.len > 0: fail("shard validation failed")
  for s in shards: echo "using ", s.name, "  [", s.source, "]"
  # 2. resolve params (prompt if needed)
  var needed: seq[string]
  for s in shards:
    for p in s.params:
      if p notin needed: needed.add p
  let ps = resolveParams(needed, parseCliParams(param), o)
  # 3+4. render and plan without writing
  let changes = planShards(shards, ps, o)
  if changes.len == 0:
    echo "nothing to do (already up to date)"
    return
  let dirty = dirtyPaths(changes.mapIt(relativePath(it.path, getCurrentDir())))
  if dirty.len > 0:
    stderr.writeLine "warning: uncommitted changes in: " & dirty.join(", ")
  # 5. diff + confirm
  for ch in changes: showChange(ch)
  if o.dryRun:
    echo "dry run: nothing written"
    return
  if not confirm("Apply " & $changes.len & " change(s)?", o):
    echo "aborted"
    return
  # 6. apply atomically
  applyChanges(changes)
  echo "done. Undo with: git restore ."
  # [[run]] entries: always printed; confirmed separately even under --yes
  var ro = o
  ro.yes = o.allowRun
  for s in shards:
    for cmd in s.runs:
      echo "shard ", s.name, " wants to run: ", cmd
      if confirm("Run it?", ro):
        if execShellCmd(cmd) != 0: stderr.writeLine "warning: command failed: " & cmd

proc cmdAdd*(args: seq[string], param: seq[string] = @[], yes = false, dryRun = false,
             verbose = false, keep = false, allowRun = false): int =
  guarded: doAdd(args, param, mkOpts(yes, dryRun, verbose, keep, allowRun))

proc cmdCheck*(args: seq[string]): int =
  guarded:
    if args.len > 1: fail("usage: velle check [path]")
    let target = if args.len == 1: args[0] else: getCurrentDir()
    let shards = shardsForCheck(target)
    echo "checking ", shards.len, " shard(s) under ", target
    let report = validateShards(shards)
    printReport(report)
    if report.errors.len > 0: fail("shard validation failed")
    echo "ok"

# ---- other commands ----------------------------------------------------------------

proc cmdInit*(yes = false, dryRun = false, verbose = false): int =
  guarded: initProject(mkOpts(yes, dryRun, verbose))

proc cmdNew*(args: seq[string], user = false, yes = false, dryRun = false,
             verbose = false): int =
  guarded:
    if args.len < 1: fail("usage: velle new <name> [files...]")
    newShard(args[0], args[1 .. ^1], user, mkOpts(yes, dryRun, verbose))

proc cmdRemote*(args: seq[string], pin = "", refresh = false): int =
  ## TODO: spec says `--ref`; cligen can't name a param `ref` (keyword), so `--pin` for now.
  guarded:
    if args.len < 1: fail("usage: velle remote add|list|remove|refresh ...")
    case args[0]
    of "add":
      if args.len != 3: fail("usage: velle remote add <name> <git-url> [--pin <tag|commit>]")
      addRemote(Remote(name: args[1], url: args[2], pin: pin), refresh)
    of "list":
      for r in loadRemotes():
        echo r.name, "  ", r.url, (if r.pin.len > 0: "  @" & r.pin else: "")
    of "remove":
      if args.len != 2: fail("usage: velle remote remove <name>")
      removeRemote(args[1])
    of "refresh":
      for r in loadRemotes():
        if args.len == 1 or r.name == args[1]:
          refreshRemote(r)
          echo "refreshed ", r.name
    else: fail("unknown remote action: " & args[0])

proc cmdSearch*(args: seq[string]): int =
  guarded:
    if args.len != 1: fail("usage: velle search <term>")
    let term = args[0].toLowerAscii
    for s in allShards():
      if term in s.name.toLowerAscii or term in s.description.toLowerAscii:
        echo s.name, "  [", s.source, "]  ", s.description

