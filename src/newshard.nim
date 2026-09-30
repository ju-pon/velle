## newshard.nim -- `velle new`: skeleton creation and param-extraction heuristics.
import std/[os, strutils, sequtils]
import util, params

proc newShard*(name: string, files: seq[string], user: bool, o: Options) =
  let base = if user: configDir() / "shards" else: getCurrentDir() / ".velle" / "shards"
  let dir = base / name
  if dirExists(dir): fail("shard already exists: " & dir)
  createDir(dir / "files")
  var used: seq[string]
  var entries = ""
  for f in files:
    if not fileExists(f): fail("no such file: " & f)
    let dest = relativePath(absolutePath(f), getCurrentDir()).replace('\\', '/')
    var text = readFile(f).replace("{{", "\\{{")     # escape literal braces first
    for pname in ["author", "email", "name", "year"]:   # heuristic: known values -> holes
      let v = peekParam(pname)
      if v.len > 0 and v in text:
        let n = text.count(v)
        if confirm("Replace " & $n & "x '" & v & "' with {{" & pname & "}} in " & dest & "?", o):
          text = text.replace(v, "{{" & pname & "}}")
          if pname notin used: used.add pname
    createDir(parentDir(dir / "files" / dest))
    writeFile(dir / "files" / dest, text)
    entries.add "\n[[file]]\nsrc  = " & tomlQuote("files/" & dest) &
                "\ndest = " & tomlQuote(dest) & "\nmode = \"create\"   # create | append | region\n"
  let toml = "name        = " & tomlQuote(name) & "\ndescription = \"\"\nparams      = [" &
             used.mapIt(tomlQuote(it)).join(", ") & "]\nrequires    = []\n" & entries
  writeFile(dir / "shard.toml", toml)
  echo "created ", dir

