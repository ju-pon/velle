version     = "0.1.0"
author      = "Juliette Ponsonnet"
description = "Inject parameterized shards (licences, gitignores, CI, ...) into a project"
license     = "BSD-3-Clause"
srcDir      = "src"
bin         = @["velle"]

requires "nim >= 2.0.0"
requires "cligen >= 1.6.0"
requires "parsetoml >= 0.7.0"

task test, "run tests":
  exec "nim c -r --hints:off tests/test_render.nim"
  exec "nim c -r --hints:off tests/test_apply.nim"
  exec "nim c -r --hints:off tests/test_golden.nim"

