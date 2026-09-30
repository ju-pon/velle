## remote.nim -- remote config, git clone/fetch, cache.
import std/[os, strutils]
import util

type
  Remote* = object
    name*, url*, pin*: string   ## pin = tag or commit ("" tracks default branch)

let defaultRemote* = Remote(name: "ju-pon", url: "git@github.com:ju-pon/velle-shards.git")

proc configPath*(): string = configDir() / "config.toml"
proc remoteDir*(r: Remote): string = cacheDir() / "remotes" / r.name

proc loadRemotes*(): seq[Remote] =
  ## No config file yet -> the preconfigured official remote.
  if not fileExists(configPath()): return @[defaultRemote]
  let t = loadToml(configPath())
  for rt in tomlTables(t, "remote"):
    result.add Remote(name: tomlStr(rt, "name"), url: tomlStr(rt, "url"),
                      pin: tomlStr(rt, "ref"))

proc saveRemotes*(rs: seq[Remote]) =
  createDir(configDir())
  var s = ""
  for r in rs:
    s.add "[[remote]]\nname = " & tomlQuote(r.name) & "\nurl  = " & tomlQuote(r.url) & "\n"
    if r.pin.len > 0: s.add "ref  = " & tomlQuote(r.pin) & "\n"
    s.add "\n"
  writeFile(configPath(), s)

proc runGit(args: openArray[string], dir = "") =
  let (o, c) = git(args, dir)
  if c != 0: fail("git " & args[0] & " failed: " & o.strip())

proc cloneRemote*(r: Remote) =
  let d = remoteDir(r)
  createDir(parentDir(d))
  try:
    if r.pin.len == 0:
      runGit(["clone", "-q", "--depth", "1", r.url, d])
    else:
      # Works for tags and (server permitting) commits; checked out detached.
      createDir(d)
      runGit(["init", "-q"], d)
      runGit(["remote", "add", "origin", r.url], d)
      runGit(["fetch", "-q", "--depth", "1", "origin", r.pin], d)
      runGit(["checkout", "-q", "--detach", "FETCH_HEAD"], d)
  except VelleError:
    removeDir(d)
    raise

proc ensureCloned*(r: Remote) =
  if not dirExists(remoteDir(r)): cloneRemote(r)

proc refreshRemote*(r: Remote) =
  let d = remoteDir(r)
  if not dirExists(d):
    cloneRemote(r)
  elif r.pin.len == 0:
    runGit(["fetch", "-q", "--depth", "1", "origin"], d)
    runGit(["reset", "-q", "--hard", "FETCH_HEAD"], d)
  else:
    runGit(["fetch", "-q", "--depth", "1", "origin", r.pin], d)
    runGit(["checkout", "-q", "--detach", "FETCH_HEAD"], d)

proc addRemote*(r: Remote, refresh = false) =
  var rs = loadRemotes()
  for x in rs:
    if x.name == r.name: fail("remote already exists: " & r.name)
  rs.add r
  saveRemotes(rs)
  if refresh: refreshRemote(r)

proc removeRemote*(name: string) =
  var rs: seq[Remote]
  var found = false
  for x in loadRemotes():
    if x.name == name: found = true
    else: rs.add x
  if not found: fail("no such remote: " & name)
  saveRemotes(rs)
  removeDir(remoteDir(Remote(name: name)))

