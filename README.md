# Maki Auto Approve

A [Maki](https://maki.sh/) plugin that uses a model to intelligently auto-approve
tool calls and escalate risky or uncertain calls to Maki's normal permission
prompt. Each approval applies once; existing allow and deny rules still apply.

Requires **Maki 0.6.4+** with a working model provider. No extra runtime or API key.

## Installation

Create or edit your global `~/.config/maki/init.lua` and add:

```lua
maki.pack.add({
  { src = "https://github.com/glitchassassin/maki-auto-approve", version = "v0.4.0" },
})
```

Run `maki` in a terminal and accept the installation and
[permission prompts](docs/installation.md#required-package-permissions).
Inside Maki, run `/auto-approve` to confirm the plugin loaded.

## Configuration

Defaults use the current model/provider and the Codex Guardian policy. To
customize, add this to the same `init.lua`, merging into any existing
`maki.setup()` call:

```lua
maki.setup({
  plugins = {
    ["maki-auto-approve"] = {
      reviewer_model = "", -- Inherit, or set "provider/model-id".
      reviewer_timeout_ms = 30000, -- Fall back to human approval after 30 seconds.
    },
  },
})
```

Settings are optional. Run `/reload` inside Maki or restart after edits.

## Local development

Requires Git, a POSIX shell, Lua 5.4/5.5, and Python 3.11+.

If switching from a managed install, remove its package declaration and plugin
settings from `init.lua`, then run `/reload` and `/packdel maki-auto-approve`
inside Maki before linking your checkout.

```sh
git clone https://github.com/glitchassassin/maki-auto-approve.git
cd maki-auto-approve
sh scripts/install-local.sh
lua tests/run.lua
python3 scripts/codex-prompts.py
python3 tests/integration.py
```

The installer symlinks your checkout into Maki; no build step is needed. Run
`/reload` inside Maki or restart to load the checkout and subsequent edits.

## Documentation

- [Installation and permissions](docs/installation.md)
- [Configuration reference](docs/configuration.md)
- [Development guide](docs/development.md)
- [Approval policy, evidence, and security limits](docs/approval-policy.md)
- [Design decisions and rationale](docs/design.md)
- [Release procedure](docs/releasing.md) and [changelog](CHANGELOG.md)
