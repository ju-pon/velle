## Golden tests: each dir in tests/golden has shard/, params.toml, input/, expected/.
## Also checks idempotence: a second apply must plan zero changes.
import std/[unittest, os, strutils]
import apply, shard, params, util

let goldenDir = currentSourcePath().parentDir / "golden"

suite "golden":
  for case_ in walkDirs(goldenDir / "*"):
    test extractFilename(case_):
      let work = getTempDir() / ("velle-golden-" & extractFilename(case_))
      removeDir(work)
      copyDir(case_ / "input", work)
      let prev = getCurrentDir()
      setCurrentDir(work)
      defer:
        setCurrentDir(prev)
        removeDir(work)
      let s = loadShard(case_ / "shard", "test", extractFilename(case_))
      let ps = loadFlat(case_ / "params.toml")
      let o = Options()
      applyChanges(planShards(@[s], ps, o))
      for f in walkDirRec(case_ / "expected"):
        let rel = relativePath(f, case_ / "expected")
        check readFile(work / rel) == readFile(f)
      check planShards(@[s], ps, o).len == 0      # idempotent

