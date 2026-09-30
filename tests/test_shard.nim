import std/[unittest, os]
import ../src/shard

suite "shard dependencies":
  test "resolve require-only shard with singular require key":
    let work = getTempDir() / ("velle-shard-test-" & $getCurrentProcessId())
    removeDir(work)
    createDir(work / ".velle" / "shards" / "base")
    createDir(work / ".velle" / "shards" / "bundle")
    writeFile(work / ".velle" / "shards" / "base" / "shard.toml",
      "name = \"base\"\nparams = []\n")
    writeFile(work / ".velle" / "shards" / "bundle" / "shard.toml",
      "name = \"bundle\"\nparams = []\nrequire = [\"base\"]\n")
    let previous = getCurrentDir()
    setCurrentDir(work)
    defer:
      setCurrentDir(previous)
      removeDir(work)
    let resolved = resolveWithRequires("bundle")
    check resolved.len == 2
    check resolved[0].name == "base"
    check resolved[1].name == "bundle"
    check resolved[1].files.len == 0
    check resolved[1].requires == @["base"]

