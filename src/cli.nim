## cli.nim -- command procs (cligen wiring lives in velle.nim).
import std/[os, strutils, sequtils]
import util, params, shard, apply, diff, remote, newshard

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

proc doAdd(args, param: seq[string], o: Options) =
  if args.len != 1: fail("usage: velle add <shard> [--param k=v]")
  # 1. resolve shard + requires
  let shards = resolveWithRequires(args[0])
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

