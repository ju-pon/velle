## newshard.nim -- `velle new`: skeleton creation and param-extraction heuristics.
import std/[os, strutils, sequtils]
import util, params

proc newShard*(name: string, files: seq[string], user: bool, o: Options) =
  let base = if user: configDir() / "shards" else: getCurrentDir() / ".velle" / "shards"
  let dir = base / name
  
  # Check for existing directory (always, even in dry-run)
  if dirExists(dir): fail("shard already exists: " & dir)
  
  # Validate all files exist before processing
  for f in files:
    if not fileExists(f): fail("no such file: " & f)
  
  var used: seq[string]
  var entries = ""
  var replacements: seq[tuple[file: string, replacements: seq[tuple[param: string, value: string, count: int]]]]
  
  # Process files and collect replacement information
  for f in files:
    let dest = relativePath(absolutePath(f), getCurrentDir()).replace('\\', '/')
    var text = readFile(f).replace("{{", "\\{{")     # escape literal braces first
    var fileReplacements: seq[tuple[param: string, value: string, count: int]]
    
    for pname in ["author", "email", "name", "year"]:   # heuristic: known values -> holes
      let v = peekParam(pname)
      if v.len > 0 and v in text:
        let n = text.count(v)
        fileReplacements.add((param: pname, value: v, count: n))
    
    if fileReplacements.len > 0:
      replacements.add((file: dest, replacements: fileReplacements))
    
    entries.add "\n[[file]]\nsrc  = " & tomlQuote("files/" & dest) &
                "\ndest = " & tomlQuote(dest) & "\nmode = \"create\"   # create | append | region\n"
  
  # Show what would be created in dry-run mode
  if o.dryRun:
    echo "dry run: would create shard at ", dir
    echo "dry run: would create directory ", dir / "files"
    for f in files:
      let dest = relativePath(absolutePath(f), getCurrentDir()).replace('\\', '/')
      echo "dry run: would copy ", f, " to files/", dest
    
    # Show potential replacements that would be offered
    var potentialParams: seq[string]
    for repl in replacements:
      for r in repl.replacements:
        echo "dry run: would offer to replace ", r.count, "x '", r.value, "' with {{", r.param, "}} in ", repl.file
        if r.param notin potentialParams: potentialParams.add r.param
    
    echo "dry run: would write shard.toml with params: [", potentialParams.mapIt(tomlQuote(it)).join(", "), "]"
    return
  
  # Create the shard directory structure
  createDir(dir / "files")
  
  # Process each file with confirmation for replacements
  for f in files:
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
  
  # Create shard.toml
  let toml = "name        = " & tomlQuote(name) & "\ndescription = \"\"\nparams      = [" &
             used.mapIt(tomlQuote(it)).join(", ") & "]\nrequires    = []\n" & entries
  writeFile(dir / "shard.toml", toml)
  echo "created ", dir

