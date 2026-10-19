# Installation

Maki Auto Approve reduces interruptions from routine permission prompts while
leaving calls that need human review in Maki's normal approval flow. It evaluates
the pending action's risk and authorization using conversation evidence and
optional file inspection. Read the [approval policy](approval-policy.md) for the
exact rules, including when authorized high-risk actions can be approved.

## Prerequisites

- Maki **0.6.4 or newer**; check with `maki --version` in your terminal.
- A working model/provider in Maki. If you are starting from scratch, follow
  [Maki's quick start](https://maki.sh/docs/quick-start/) to install Maki, connect a
  provider, and run a first session.
- Git available on `PATH` for managed installation from this repository.

The plugin is a native Lua package. It needs no separate Lua interpreter, Python
runtime, or plugin-specific API key for normal use. Reviews use your existing
Maki provider and its normal usage limits and costs. Lua and Python are needed
only for [development checks](development.md).

## Install a release

1. Open or create your global `~/.config/maki/init.lua`. Create its parent
   directory if needed. If you use a custom Maki configuration location, edit its
   global `init.lua` instead.
2. Add the package declaration below. If you already declare packages, add the
   entry to that list. Package declarations belong in the global configuration.
3. Start `maki` in an interactive terminal, or restart an existing instance.
   Accept Maki's package installation prompt and its requested capabilities.

```lua
maki.pack.add({
  { src = "https://github.com/glitchassassin/maki-auto-approve", version = "v0.3.1" },
})
```

No plugin settings are required. Defaults enable review using the calling
model/provider and the pinned Codex Guardian policy. To customize them, add the
optional [configuration example](configuration.md#global-settings) to the same
file. Maki permits one `maki.setup()` call per init file, so merge settings into
an existing call.

Managed installation records the resolved commit in `pack-lock.json`. See
[Maki's Lua package reference](https://maki.sh/docs/packages/) for package approval
and lockfile behavior.

## Required package permissions

The [package manifest](../plugin.toml) requests all six Maki plugin permissions:

| Permission | What it grants the package | Why Maki Auto Approve requires it |
| --- | --- | --- |
| `fs_read` | Read files and filesystem metadata. | Inspect paths, read files, list directories, and revalidate inspected evidence. |
| `fs_write` | Create, change, and remove files. | Approve calls to tools that can write files. |
| `net` | Make outbound network requests. | Approve calls to network-capable tools. |
| `run` | Start processes. | Approve calls to shell and other process-running tools. |
| `env` | Read process environment variables. | Approve calls to tools that can read the environment. |
| `agent` | Start model turns and sessions. | Create the model session that reviews each pending call. |

Maki requires an approving plugin to hold the target tool's capabilities. Tools
with undeclared capabilities, including MCP tools, require all six. Separately,
the `agent.user_message` hook requires all six even though this plugin uses it
only to invalidate pending approvals when new instructions arrive. These are host
requirements; removing a permission can prevent the hook from running or leave
affected tool calls to normal human approval. See
[Maki's capability and hook reference](https://maki.sh/docs/lua-api/#makiapiset_slot).

These are broad grants to the installed package code. The reviewing model is
given only [three bounded read-only inspection tools](approval-policy.md#inspection-tools);
it has no shell, write, network, environment, or delegation tool. The package's
review path inspects evidence and returns a decision; Maki executes an approved
tool call through its normal dispatcher. Review evidence is sent to the selected
model provider as described in [data sent to the reviewer](approval-policy.md#data-sent-to-the-reviewer).

## Verify it loaded

Inside Maki, run `/auto-approve`. A freshly loaded plugin opens a history window
with no reviews recorded yet; close it with `q` or Escape. Slash commands in
these guides are entered inside Maki, not in your shell.

For a harmless first check, ask Maki: **Use the bash tool to run `pwd` in this
project.** If that shell call would normally require a permission prompt, it
triggers a review. An accepted review approves the call once and marks the tool
row. A deferred review shows a notice with its rationale, followed by the normal
permission prompt. Run `/auto-approve` again to inspect the outcome.

An existing native allow rule may let `pwd` run without a review entry. Calls
covered by native allow or deny rules, or YOLO mode (which skips permission
prompts), do not reach the reviewer.

## Updates and removal

Run `/packupdate maki-auto-approve` inside Maki to review a proposed update. The
declaration above selects `v0.3.1`; choose the desired release in `version` when
moving to a newer tag. A recorded lockfile commit takes precedence over edits to
`version` until an update resolves the declaration. Maki shows the old and new
commits and any capability changes before applying an accepted update. See
[Maki's update and pinning rules](https://maki.sh/docs/packages/#pinned-revisions).

To remove the managed package, remove its `maki.pack.add` entry and any associated
`plugins["maki-auto-approve"]` settings, reload Maki, then run
`/packdel maki-auto-approve`. To temporarily disable reviews, use
[`enabled = false`](configuration.md#disable-reviews).

For an editable checkout, follow [local development](development.md#local-setup).
Use one installation method per package name; remove a managed installation
before linking a development checkout.

## Troubleshooting

- **No installation prompt or unknown `/auto-approve` command:** start Maki
  interactively, check startup errors, confirm the global package declaration,
  and accept both install and capability prompts. Headless mode cannot accept
  those prompts. Also check that the plugin is enabled.
- **Unknown plugin name in configuration:** install or declare the package so
  Maki recognizes `maki-auto-approve`. Keep its declaration in global `init.lua`.
- **Calls still ask for approval:** inspect `/auto-approve` and the preceding
  notice. A model denial, unavailable provider, timeout, failed inspection, or
  changed evidence returns to the ordinary prompt. This is expected fallback.
- **Project settings have no effect:** check [folder trust and reload](configuration.md#project-settings-and-folder-trust).
- **Local installer refuses an existing package:** resolve the installation
  conflict using [development setup](development.md#local-setup); the installer
  deliberately does not overwrite it.

[Documentation index](README.md)
