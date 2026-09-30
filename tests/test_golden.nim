## Golden tests: each dir in tests/golden has shard/, params.toml, input/, expected/.
## Also checks idempotence: a second apply must plan zero changes.
import std/[unittest, os]
import ../src/[apply, shard, params, util]

let goldenDir = currentSourcePath().parentDir / "golden"

suite "golden":
  for casee in walkDirs(goldenDir / "*"):
    test extractFilename(casee):
      let work = getTempDir() / ("velle-golden-" & extractFilename(casee))
      removeDir(work)
      copyDir(casee / "input", work)
      let prev = getCurrentDir()
      setCurrentDir(work)
      defer:
        setCurrentDir(prev)
        removeDir(work)
      let s = loadShard(casee / "shard", "test", extractFilename(casee))
      let ps = loadFlat(casee / "params.toml")
      let o = Options()
      applyChanges(planShards(@[s], ps, o))
      for f in walkDirRec(casee / "expected"):
        let rel = relativePath(f, casee / "expected")
        check readFile(work / rel) == readFile(f)
      check planShards(@[s], ps, o).len == 0      # idempotent

