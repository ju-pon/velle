## validate.nim -- shard authoring validation.
import std/[os, strutils]
import shard, util

type
  ValidationReport* = object
    errors*, warnings*: seq[string]

proc addUnique(items: var seq[string], item: string) =
  if item notin items: items.add item

proc templateParams(text: string, shardName, fileName: string,
                   report: var ValidationReport): seq[string] =
  var i = 0
  while i < text.len:
    if text.continuesWith("\\{{", i):
      i += 3
    elif text.continuesWith("{{", i):
      let close = text.find("}}", i + 2)
      if close < 0:
        report.errors.add "shard " & shardName & ", file " & fileName &
          ": unclosed '{{'"
        break
      let name = text[i + 2 ..< close].strip()
      if name.len == 0:
        report.errors.add "shard " & shardName & ", file " & fileName &
          ": empty template parameter"
      else:
        result.addUnique name
      i = close + 2
    else:
      inc i

proc validateShard*(s: Shard): ValidationReport =
  ## Validate declarations and template references without prompting or writing.
  var used: seq[string]
  for f in s.files:
    let source = s.root / f.src
    if not fileExists(source):
      result.errors.add "shard " & s.name & ": template file not found: " & f.src
      continue
    for name in templateParams(readFile(source), s.name, f.src, result):
      used.addUnique name
  for name in used:
    if name notin s.params:
      result.errors.add "shard " & s.name & ", parameter '" & name &
        "' is used but not declared"
  for name in s.params:
    if name notin used:
      result.warnings.add "shard " & s.name & ", parameter '" & name &
        "' is declared but unused"

proc printReport*(report: ValidationReport) =
  for warning in report.warnings:
    stderr.writeLine "warning: " & warning
  for error in report.errors:
    stderr.writeLine "error: " & error

proc validateShards*(shards: seq[Shard]): ValidationReport =
  for s in shards:
    let report = validateShard(s)
    result.errors.add report.errors
    result.warnings.add report.warnings

proc shardsForCheck*(path: string): seq[Shard] =
  ## Resolve a check target without consulting configured remotes.
  let target = absolutePath(path)
  if fileExists(target):
    if target.extractFilename != "shard.toml":
      fail("check path is not a shard.toml: " & path)
    return @[loadShard(target.parentDir, "check", target.parentDir.extractFilename)]
  if not dirExists(target): fail("check path not found: " & path)
  if fileExists(target / "shard.toml"):
    return @[loadShard(target, "check", target.extractFilename)]
  result = scanSource(Source(label: "check", dir: target))
  if result.len == 0: fail("no shard.toml found under: " & path)

