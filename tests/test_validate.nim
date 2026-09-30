import std/[unittest, os, strutils]
import ../src/[shard, validate]

proc makeShard(dir, params, body: string): Shard =
  createDir(dir / "files")
  writeFile(dir / "files" / "template.txt", body)
  writeFile(dir / "shard.toml", "name = \"demo\"\nparams = [" & params &
    "]\n[[file]]\nsrc = \"files/template.txt\"\ndest = \"output.txt\"\n")
  loadShard(dir, "test", "demo")

suite "shard validation":
  test "reports undeclared template parameter":
    let root = getTempDir() / ("velle-validate-undeclared-" & $getCurrentProcessId())
    removeDir(root)
    let report = validateShard(makeShard(root, "", "hello {{name}}\n"))
    check report.errors.len == 1
    check report.errors[0].find("name") >= 0
    check report.errors[0].find("demo") >= 0
    removeDir(root)

  test "warns about declared but unused parameter":
    let root = getTempDir() / ("velle-validate-unused-" & $getCurrentProcessId())
    removeDir(root)
    let report = validateShard(makeShard(root, "\"name\"", "hello\n"))
    check report.errors.len == 0
    check report.warnings.len == 1
    check report.warnings[0].find("unused") >= 0
    removeDir(root)

  test "ignores escaped template marker":
    let root = getTempDir() / ("velle-validate-escaped-" & $getCurrentProcessId())
    removeDir(root)
    let report = validateShard(makeShard(root, "", "literal \\{{name}}\n"))
    check report.errors.len == 0
    check report.warnings.len == 0
    removeDir(root)

  test "reports malformed template marker":
    let root = getTempDir() / ("velle-validate-malformed-" & $getCurrentProcessId())
    removeDir(root)
    let report = validateShard(makeShard(root, "", "hello {{name\n"))
    check report.errors.len == 1
    check report.errors[0].find("unclosed") >= 0
    removeDir(root)

