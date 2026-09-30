## diff.nim -- diff rendering. Prefers `git diff --no-index`, falls back to a built-in line diff.
import std/[os, strutils, sequtils, options]
import util, apply

proc simpleDiff*(a, b: string): string =
  ## LCS line diff; prints only changed lines.
  let x = a.splitLines
  let y = b.splitLines
  var t = newSeqWith(x.len + 1, newSeq[int](y.len + 1))
  for i in countdown(x.len - 1, 0):
    for j in countdown(y.len - 1, 0):
      t[i][j] = if x[i] == y[j]: t[i + 1][j + 1] + 1 else: max(t[i + 1][j], t[i][j + 1])
  var i, j = 0
  while i < x.len and j < y.len:
    if x[i] == y[j]: inc i; inc j
    elif t[i + 1][j] >= t[i][j + 1]: result.add "-" & x[i] & "\n"; inc i
    else: result.add "+" & y[j] & "\n"; inc j
  while i < x.len: result.add "-" & x[i] & "\n"; inc i
  while j < y.len: result.add "+" & y[j] & "\n"; inc j

proc gitDiff(rel, oldText, newText: string): Option[string] =
  let tmp = getTempDir() / ("velle-diff-" & $getCurrentProcessId())
  try:
    createDir(tmp / "a" / parentDir(rel))
    createDir(tmp / "b" / parentDir(rel))
    writeFile(tmp / "a" / rel, oldText)
    writeFile(tmp / "b" / rel, newText)
    let (o, c) = git(["diff", "--no-index", "--no-color", "--src-prefix=", "--dst-prefix=",
                      "--", "a" / rel, "b" / rel], tmp)
    if c in [0, 1] and o.len > 0: result = some(o)   # exit 1 == differences found
  except CatchableError: discard
  finally:
    removeDir(tmp)

proc showChange*(ch: Change) =
  let rel = relativePath(ch.path, getCurrentDir()).replace('\\', '/')
  let old = if ch.oldText.isSome: ch.oldText.get else: ""
  echo (if ch.oldText.isSome: "~ " else: "+ "), rel, "  (", ch.shard, ")"
  let d = gitDiff(rel, old, ch.newText)
  if d.isSome: echo d.get
  else: echo simpleDiff(old, ch.newText)

