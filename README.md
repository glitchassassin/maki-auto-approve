# Maki Auto Approve

A native Maki Lua package that reviews pending permission prompts with a model.
It automatically approves qualifying calls once. Every other outcome goes back
to Maki's normal permission prompt, with the review rationale shown in a notice.

Requires Maki **0.6.4 or newer**. No additional runtime or model API key is needed;
the reviewer inherits the current Maki model/provider unless configured otherwise.

## Managed installation

After this repository is published, add its Git URL to your global
`~/.config/maki/init.lua` (replace `OWNER` with the repository owner):

```lua
maki.pack.add({
  { src = "https://github.com/OWNER/maki-auto-approve", version = "v0.2.0" },
})
```

Maki asks to install the package and approve its requested capabilities. The
resolved commit is saved in `pack-lock.json`. `/packupdate maki-auto-approve`
reviews updates; to remove the package, remove its declaration, reload, and run
`/packdel maki-auto-approve`. Package declarations belong in the global init file.

The same manager can install a committed local Git repository without publishing:

```lua
maki.pack.add({
  { src = "/absolute/path/to/maki-auto-approve", version = "v0.2.0" },
})
```

Managed installation uses the tagged Git contents. The development installer
below follows your working checkout, including uncommitted edits. Do not install
both under the same package name.

## Local development installation

```sh
sh scripts/install-local.sh
```

The script creates a symlink under Maki's `site/pack/user/start/` directory. It
does not modify your configuration or overwrite an existing package. You can
pass a Maki data directory as its only argument. It honors `XDG_DATA_HOME` and
Maki's legacy `~/.maki` directory. Restart Maki or run `/reload` afterward.
For existing chats, send a new human message to establish authorization evidence.

To uninstall, remove that symlink and restart or reload Maki. The repository and
your Maki configuration can stay in place. No remote repository is required.

## Configuration

Configure the installed package through Maki's `maki.setup()` in your global
`~/.config/maki/init.lua`:

```lua
maki.setup({
  plugins = {
    ["maki-auto-approve"] = {
      reviewer_model = "", -- Inherit the calling model/provider.
      reviewer_timeout_ms = 45000,
      inspection_max_file_bytes = 65536,
      -- policy_rubric = [=[Your complete replacement reviewer rubric.]=],
    },
  },
})
```

Merge this table into an existing `maki.setup()` call; Maki permits one call per
init file. The package must be installed or declared with `maki.pack.add` so Maki
recognizes its name. All options are optional; built-in defaults enable review
using the calling model and the Codex-derived rubric.

See [examples/global.lua](examples/global.lua) for every option, its default, and
its valid range. Maki's option API accepts scalars, so names such as
`reviewer_timeout_ms` and `inspection_max_file_bytes` are flat keys. Set
`policy_rubric` to a Lua string to replace the whole rubric; Lua's `[=[...]=]`
notation supports multiline policy text. The default rubric is in
[lua/auto_approve/policy.lua](lua/auto_approve/policy.lua).

For project overrides, add settings to `<project>/.maki/init.lua`:

```lua
maki.setup({
  plugins = {
    ["maki-auto-approve"] = {
      reviewer_timeout_ms = 30000,
      inspection_max_file_bytes = 32768,
    },
  },
})
```

Maki merges global settings with the project settings it loads. Omitted project
options inherit global values; an explicitly supplied string replaces the global
string. [examples/project.lua](examples/project.lua) shows a minimal override.
Use Maki's native `enabled = false` package option to disable automatic reviews
in the relevant global or trusted project configuration.

### Native folder trust and reload

Project settings follow [Maki's folder trust](https://maki.sh/docs/folder-trust/).
When Maki trusts a folder, it loads that folder's `init.lua`, including these
options. When Maki skips an untrusted project's config, this package receives
global settings and built-in defaults. This applies to reviewer models, rubrics,
limits, and the package's `enabled` toggle. No extra project opt-in flag is needed.

Use Maki's normal `/trust`, `maki trust add`, trust-path policy, or one-run
`--trust` grant. There are no plugin-specific trust prompts, commands, or consent
records. An edit follows Maki's normal configuration lifecycle; run `/reload` or
restart Maki to apply it. Native reload rebuilds the package's options and hooks.
Existing chats need a new human message after reload to restore authorization
evidence. Until reload, the running package keeps its current settings.

Maki validates option names, scalar types, and minimums. The package also rejects
unsupported model/thinking values, oversized or empty rubrics, and values above
its limits before installing any approval hooks. Invalid options cannot grant
automatic approval; Maki reports the load/configuration error and its native
permission handling remains authoritative.

### Migrating from the earlier local version

Move settings from `auto-approve.toml` into the Lua package table, for example
`[reviewer] model` becomes `reviewer_model` and `[policy] rubric` becomes
`policy_rubric`. The old TOML files and `auto-approve-trust.json` are no longer read
or written and may be removed. `/auto-approve-trust` and `/auto-approve-untrust`
are removed. Maki's native folder trust controls all project configuration.

## Permission behavior

The package wraps only `permission.prompt` to grant approvals. Native permission
resolution happens first:

- Explicit allow rules execute without a model review.
- Explicit deny rules block without a model review.
- YOLO bypasses review.
- A pending ordinary prompt invokes the reviewer.
- A valid policy-consistent allow approves that exact call once, without saving a rule.
- Denials, uncertainty, invalid JSON, unavailable providers, timeouts, cancellation,
  missing evidence, changed instructions, or failed inspections
  return control to the normal permission prompt.

Prompts explicitly forced by another plugin's `ask` hook remain human-only; Maki
does not offer them to this package. In `maki -p`, nobody can answer a fallback
prompt, so Maki denies it normally. The package never bypasses that behavior.
Builtin, MCP, ACP, and nested tool calls are covered whenever Maki routes them
through the same permission hook. Tools that never prompt remain unaffected.

The default Codex-derived rubric assesses intrinsic risk and user authorization
separately, including sensitive egress, credentials, destruction, and persistent
security changes. Critical-risk actions and high-risk allows without at least
medium authorization always defer to a human, even with a custom rubric.

## Review evidence and inspection

Original human messages from Maki's TUI, ACP, or headless input are captured
separately from conversation evidence. Plugin-generated messages and assistant
claims cannot establish user authorization. Recent visible messages and tool
evidence are included under an untrusted-data label. Thinking and image contents
are excluded. The exact pending action is never truncated into an approval.

Captured human instructions survive compaction in the current process. They are
bounded, remain in memory, and are cleared on session reset/end. After a plugin
reload or process restart, old transcript messages alone cannot grant authority;
send a fresh human message. Delegated calls use the owning chat's captured human
instructions. New human instructions invalidate an approval still in flight.

The reviewer receives only these tools, bound to its active review:

- `auto_approve_inspect_path`: existence, file type, size, modification time.
- `auto_approve_read_file`: bounded UTF-8 reads of regular files.
- `auto_approve_list_directory`: bounded one-level listings.

No shell, network, MCP, mutation, or delegation tool is passed to the reviewer.
Inspection tools are not advertised to the main model. Failed inspections require
human review. Inspected file contents and path metadata are checked again before
an allow is accepted. Reads follow Maki's filesystem API, including symlinks; they
are not restricted to the project tree or protected by a separate OS sandbox.
Filesystem changes after the final check remain possible. Directory output is
bounded; Maki's API enumerates the directory before applying our output limit.

The package manifest requests all six plugin capabilities because Maki requires
them for the human-message hook and tools with undeclared capabilities, including
MCP tools. These are capabilities of the installed package code; the reviewer's
delegated tool list remains restricted to the three read-only tools above.

## Review history

Run `/auto-approve` to see recent outcomes, risk and authorization assessments,
and rationales for the current chat. Deferred reviews also show a notice before
the normal prompt. Maki marks calls approved by this package in their tool rows.
The package logs concise outcomes through Maki's logger; it does not write raw
actions, file contents, conversation evidence, or rubric text to a separate log.

## Development

```sh
lua tests/run.lua
python3 tests/integration.py
```

Unit tests use Lua 5.4/5.5 and a mocked host. Native integration tests use the installed
Maki binary, isolated temporary XDG directories, and a local fake OpenAI-compatible
provider. They make no real model calls and do not install the package in your
normal Maki configuration. Python 3 is needed only for these integration tests.

The integration suite verifies native allow/deny bypasses, one-call automatic
approval, real interactive human fallback, headless denial, restricted asynchronous
inspection, native folder trust and option merging, malformed responses, timeout
cleanup, JIT execution, and managed Git installation with capability prompts and
a locked commit.

The Ubuntu CI workflow pins Maki 0.6.4 and checks its release archive's SHA-256.
It runs the same local suites, validates the package manifest, and checks Lua,
example, and installer syntax.
See [CHANGELOG.md](CHANGELOG.md) for the release history and
[RELEASING.md](RELEASING.md) for the release procedure.

The tests validate the integration and enforcement paths, not the judgment quality
of a particular model or custom rubric. See [NOTICE](NOTICE) for policy attribution.
