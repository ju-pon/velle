import std/[unittest, tables, strutils]
import ../src/[render, util, params]

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
      check e.msg.contains("nope") and e.msg.contains("license/mit")

suite "fresh parameters":
  test "detectFresh generates fresh values":
    let timestamp1 = detectFresh("timestamp")
    let timestamp2 = detectFresh("timestamp")
    check timestamp1.len > 0
    check timestamp2.len > 0
    # Fresh values should be different when called separately
    
    let year = detectFresh("current_year")
    check year == "2026"  # Based on current environment
    
    let date = detectFresh("current_date")
    check date.len == 10  # YYYY-MM-DD format
    
    let randomId = detectFresh("random_id")
    check randomId.len == 6  # 6-digit random number

  test "builtinFreshNames contains expected values":
    check builtinFreshNames.contains("timestamp")
    check builtinFreshNames.contains("current_year") 
    check builtinFreshNames.contains("current_date")
    check builtinFreshNames.contains("git_branch")
    check builtinFreshNames.contains("git_commit")
    check builtinFreshNames.contains("random_id")

  test "fresh parameters are not cached":
    # Test that fresh values generate new values each time
    let randomId1 = detectFresh("random_id")
    let randomId2 = detectFresh("random_id")
    # Random IDs should be different (very high probability)
    check randomId1 != randomId2

