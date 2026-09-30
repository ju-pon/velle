## velle.nim -- entry point and command dispatch.
import cligen
import cli

when isMainModule:
  dispatchMulti(
    ["multi", doc = "velle: inject parameterized shards into a project\n"],
    [cmdInit, cmdName = "init", doc = "create project params (.velle/params.toml)"],
    [cmdAdd, cmdName = "add", doc = "inject a shard (with its requires)",
     help = {"param": "override a param: name=value", "yes": "skip confirmation",
             "dryRun": "show diff, never write", "verbose": "chatty output",
             "keep": "keep existing files for `create` mode",
             "allowRun": "allow shard [[run]] commands without prompting"}],
    [cmdNew, cmdName = "new", doc = "create a local shard from files",
     help = {"user": "create in ~/.config/velle/shards instead of the project"}],
    [cmdCheck, cmdName = "check", doc = "validate shard templates and parameters"],
    [cmdRemote, cmdName = "remote", doc = "remote add|list|remove|refresh"],
    [cmdSearch, cmdName = "search", doc = "search shard names/descriptions"])

