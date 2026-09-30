## render.nim -- {{param}} substitution.
import std/[strutils, tables]
import util

proc render*(text: string, params: Table[string, string], shard: string): string =
  ## `{{name}}` is replaced; `\{{` yields a literal `{{`.
  ## A missing param is a hard error naming the param and the shard.
  var i = 0
  while i < text.len:
    if text.continuesWith("\\{{", i):
      result.add "{{"
      i += 3
    elif text.continuesWith("{{", i):
      let close = text.find("}}", i + 2)
      if close < 0: fail("shard " & shard & ": unclosed '{{'")
      let name = text[i + 2 ..< close].strip()
      if name notin params:
        fail("shard " & shard & ": missing param '" & name & "'")
      result.add params[name]
      i = close + 2
    else:
      result.add text[i]
      inc i

