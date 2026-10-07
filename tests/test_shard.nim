import std/[unittest, os]
import ../src/[shard, params]

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

  test "load shard with parameter metadata":
    let work = getTempDir() / ("velle-shard-param-test-" & $getCurrentProcessId())
    removeDir(work)
    createDir(work / ".velle" / "shards" / "test-meta")
    writeFile(work / ".velle" / "shards" / "test-meta" / "shard.toml", """
name = "test-meta"
description = "Test parameter metadata"
params = ["author", "project"]

[param.author]
scope = "profile"
prompt = "Your full name"

[param.project]
scope = "project"
default = "{{name}}"
""")
    let previous = getCurrentDir()
    setCurrentDir(work)
    defer:
      setCurrentDir(previous)
      removeDir(work)
    let shard = findShard("test-meta")
    check shard.params == @["author", "project"]
    check shard.paramMeta.len == 2
    
    # Check author parameter metadata
    let authorMeta = shard.paramMeta[0]
    check authorMeta.name == "author"
    check authorMeta.scope == psProfile
    check authorMeta.prompt == "Your full name"
    check authorMeta.default == ""
    
    # Check project parameter metadata
    let projectMeta = shard.paramMeta[1]
    check projectMeta.name == "project"
    check projectMeta.scope == psProject
    check projectMeta.prompt == ""
    check projectMeta.default == "{{name}}"

