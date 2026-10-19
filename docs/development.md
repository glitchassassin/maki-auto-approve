# Development

## Prerequisites

- Maki **0.6.4+** on `PATH` for local use and native integration tests.
- Lua **5.4 or 5.5**, plus `luac`, for unit tests and syntax checks.
- Python **3.11+** for prompt verification and integration tests.
- Git and a POSIX shell/terminal. Native terminal tests use Unix PTY APIs.

No Python packages or real provider credentials are required for the checks.
To use the plugin interactively with a real model, configure your provider in
Maki as described in [installation](installation.md#prerequisites).

## Local setup

Use one installation method per package name. If you already have a managed
installation, first follow the [removal steps](installation.md#updates-and-removal),
then link your checkout:

```sh
git clone https://github.com/glitchassassin/maki-auto-approve.git
cd maki-auto-approve
sh scripts/install-local.sh
```

The installer creates a `maki-auto-approve` symlink under Maki's
`site/pack/user/start/` directory. It does not edit your configuration or
overwrite an existing package. Its data-directory selection is:

1. The supplied argument, if any: `sh scripts/install-local.sh /path/to/maki-data`.
2. The legacy `~/.maki` directory, if it exists.
3. `$XDG_DATA_HOME/maki`, or `~/.local/share/maki` if `XDG_DATA_HOME` is unset.

Start Maki or run `/reload` inside it. The symlink follows your working checkout,
including uncommitted edits; reload after changing Lua code or configuration.
No build step is required. Existing chats reuse recorded user instructions.
Optional plugin settings still go in Maki's `init.lua`; see
[configuration](configuration.md).

Maki treats packages placed by hand as trusted and grants their manifest
capabilities without the managed-install approval prompts. See
[Maki's manual installation rules](https://maki.sh/docs/packages/#install-by-hand).
Run `/auto-approve` to verify the plugin loaded.

To remove this installation, remove only the `maki-auto-approve` symlink from the
selected data directory and any plugin configuration, then reload Maki. Your
checkout remains available. Managed installation loads tagged Git contents
instead of your working tree.

## Run checks

From the repository root:

```sh
lua tests/run.lua
python3 scripts/codex-prompts.py
python3 tests/integration.py
```

Unit tests use a mocked Lua host. Native integration tests use the installed
Maki binary, isolated temporary XDG directories, and a local fake
OpenAI-compatible provider. They make no real model calls and do not install
the package in your normal Maki configuration. They need permission to bind a
local loopback port and create a controlling terminal.

The integration suite verifies native allow/deny bypasses, one-call automatic
approval, interactive human fallback, headless denial, restricted asynchronous
inspection, native folder trust and option merging, malformed responses,
timeout cleanup, JIT execution, saved-chat resume without fresh human input,
Codex's low/medium-risk outcomes with unknown authorization, minimal/wrapped
responses, high-risk denial fallback, and managed Git installation with
capability prompts and a locked commit.

The Ubuntu CI workflow pins Maki 0.6.4 and verifies the release archive's SHA-256.
It runs the same suites, validates the package manifest, and checks Lua, example,
and installer syntax. See [release validation](releasing.md#validate) for the
complete command list. These tests validate integration and enforcement, not
the judgment quality of a model or custom policy.

## Repository layout

- `plugin/auto_approve.lua`: package entry point.
- `lua/auto_approve/`: configuration, evidence selection, review orchestration,
  policy assembly, inspection tools, and permission hooks.
- `examples/`: global and project configuration examples.
- `tests/`: mocked unit tests and native Maki integration tests.
- `scripts/`: local installer and Codex prompt verification/generation.
- `vendor/codex/`: pinned upstream policy, parser reference, and source hashes.
- `docs/`: user guides, design rationale, and maintainer instructions.

## Maintain the Codex baseline

`python3 scripts/codex-prompts.py` verifies the vendored Git blob hashes and
generated Lua bundle. `python3 scripts/codex-prompts.py --write` regenerates
`lua/auto_approve/codex_prompts.lua` without network access. Edit the source
baseline deliberately and regenerate it; avoid editing only the generated file.

Review `vendor/codex/source.json` when changing the upstream revision. Keep
`LICENSE` and `NOTICE` attribution accurate. The
[vendor README](../vendor/codex/README.md) explains the source files and allowed
substitutions, and [design decisions](design.md) explains why they are pinned.

[Documentation index](README.md)
