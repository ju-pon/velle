import std/[unittest, options]
import ../src/[apply, shard, util]

proc plan(mode: InsertMode, dest, rendered, existing: string, somee = true): string =
  let f = ShardFile(src: "x", dest: dest, mode: mode)
  planFile(f, "t/lint", rendered, (if somee: some(existing) else: none(string)), false)

suite "append":
  test "adds, then is idempotent":
    let once = plan(imAppend, ".gitignore", "*.o\n", "a\n")
    check once == "a\n*.o\n"
    check plan(imAppend, ".gitignore", "*.o\n", once) == once

suite "region":
  test "appends when absent":
    check plan(imRegion, "justfile", "lint:\n  x\n", "build:\n  y\n") ==
      "build:\n  y\n# >>> velle:t-lint >>>\nlint:\n  x\n# <<< velle:t-lint <<<\n"

  test "replaces existing body":
    let old = "a\n# >>> velle:t-lint >>>\nOLD\n# <<< velle:t-lint <<<\nz\n"
    check plan(imRegion, "justfile", "NEW\n", old) ==
      "a\n# >>> velle:t-lint >>>\nNEW\n# <<< velle:t-lint <<<\nz\n"

  test "preserves CRLF and missing trailing newline":
    let old = "a\r\nb"
    let r = plan(imRegion, "justfile", "x\n", old)
    check r == "a\r\nb\r\n# >>> velle:t-lint >>>\r\nx\r\n# <<< velle:t-lint <<<"

  test "unclosed marker aborts":
    expect VelleError:
      discard plan(imRegion, "justfile", "x\n", "# >>> velle:t-lint >>>\nfoo\n")

  test "duplicate markers abort":
    let m = "# >>> velle:t-lint >>>\n# <<< velle:t-lint <<<\n"
    expect VelleError:
      discard plan(imRegion, "justfile", "x\n", m & m)

