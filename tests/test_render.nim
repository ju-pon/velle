import std/[unittest, tables]
import ../src/[render, util]

suite "render":
  let p = {"author": "Ada", "year": "2026"}.toTable

  test "substitutes":
    check render("(c) {{year}} {{ author }}", p, "t") == "(c) 2026 Ada"

  test "escape":
    check render("literal \\{{x}}", p, "t") == "literal {{x}}"

  test "missing param names param and shard":
    try:
      discard render("{{nope}}", p, "license/mit")
      fail()
    except VelleError as e:
      check "nope" in e.msg and "license/mit" in e.msg

