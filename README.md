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
  { src = "https://github.com/OWNER/maki-auto-approve", version = "v0.1.0" },
})
```

Maki asks to install the package and approve its requested capabilities. The
resolved commit is saved in `pack-lock.json`. `/packupdate maki-auto-approve`
reviews updates; to remove the package, remove its declaration, reload, and run
`/packdel maki-auto-approve`. Package declarations belong in the global init file.

The same manager can install a committed local Git repository without publishing:

```lua
maki.pack.add({
  { src = "/absolute/path/to/maki-auto-approve", version = "v0.1.0" },
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
your TOML configuration can stay in place. No remote repository is required.

## Configuration

Optional files, applied in this order:

1. Built-in defaults.
2. `<maki-config-dir>/auto-approve.toml`, normally `~/.config/maki/auto-approve.toml`.
3. `<project>/.maki/auto-approve.toml`, after explicit project-policy consent.

The project root is the nearest ancestor containing `.git` (including a worktree
`.git` file), otherwise the session's working directory. Settings merge by field;
omitted project settings inherit global values. Strings, including the rubric,
replace the inherited value. Files are reread for each review, so changes need
no reload. Invalid configuration returns the call to the normal prompt.

Copy [auto-approve.toml](auto-approve.toml) for a complete configuration and rubric,
or [examples/project.toml](examples/project.toml) for a small project override.
Neither file is required to enable the built-in policy.

```toml
enabled = true
project_overrides = true # Global only; false ignores all project overrides.

[reviewer]
model = ""              # Empty or omitted inherits the active Maki model.
thinking = ""           # Inherit; optional off/minimal/low/medium/high/xhigh/max/adaptive.
timeout_ms = 45000      # 100–55000; stays inside Maki's 60-second hook window.
max_inspections = 8     # 1–32 calls per review.
max_concurrent = 2      # 1–8 active reviews; excess calls go to the human prompt.

[context]
max_messages = 40       # 1–200 recent transcript messages.
max_bytes = 48000       # 2048–200000 bytes for the action and conversation payload.
max_user_bytes = 16000  # 512–64000 bytes of captured human instructions.

[inspection]
enabled = true
max_file_bytes = 65536       # 256–262144 bytes per regular UTF-8 file.
max_directory_entries = 100 # 1–1000 entries in a one-level listing.

[logging]
history_size = 50       # 1–200 recent results per session, held in memory.

# [policy]
# rubric = '''Your complete replacement rubric.'''
```

### Explicit project-policy trust

When a project supplies overrides, calls return to the normal human prompt until
you run `/auto-approve-trust`. The command displays the checkout, exact TOML file,
and the effect on the reviewer model/provider and rubric. Press `y` to confirm;
closing the window or any other non-navigation key cancels. If you are already
at a permission prompt, resolve it first, then run the command and retry the task.

Consent applies to one checkout and the exact file bytes, including comments.
Any file change requires another confirmation. Trust records live in your global
Maki config directory as `auto-approve-trust.json`, outside the repository. Use
`/auto-approve-untrust` to revoke consent. Revocation and new user instructions
invalidate approvals in flight. No model-facing tool can grant policy trust.

A project can always set `enabled = false` to request human approvals. An empty
or comment-only file needs no consent. All other overrides require confirmation,
including selecting another model/provider. An untrusted override never starts
a reviewer or sends it conversation/file evidence.

This policy consent is separate from Maki's executable `init.lua` folder trust.
It also applies when Maki's folder is already trusted or started with `--trust`.
Headless/ACP runs can use previously confirmed policies but cannot grant consent.
Set `project_overrides = false` globally to ignore every project override; projects
cannot turn that switch on. Treat the global config and consent store as trusted
local configuration, with the same filesystem protection as your Maki settings.

The self-contained parser supports the TOML forms used here: bare/dotted keys,
tables, booleans, decimal integers, and basic/literal strings including multiline
strings. Other TOML types and unknown settings are rejected. There is no Lua
evaluation, shell interpolation, environment expansion, or external parser.

## Permission behavior

The package wraps only `permission.prompt` to grant approvals. Native permission
resolution happens first:

- Explicit allow rules execute without a model review.
- Explicit deny rules block without a model review.
- YOLO bypasses review.
- A pending ordinary prompt invokes the reviewer.
- A valid policy-consistent allow approves that exact call once, without saving a rule.
- Denials, uncertainty, invalid JSON, unavailable providers, timeouts, cancellation,
  missing evidence, changed instructions/configuration, or failed inspections
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
inspection, project-policy consent, malformed responses, timeout cleanup, JIT
execution, and managed Git installation with capability prompts and a locked commit.

The Ubuntu CI workflow pins Maki 0.6.4 and checks its release archive's SHA-256.
It runs the same local suites, validates TOML, and checks Lua and installer syntax.
See [CHANGELOG.md](CHANGELOG.md) for the release history and
[RELEASING.md](RELEASING.md) for the release procedure.

The tests validate the integration and enforcement paths, not the judgment quality
of a particular model or custom rubric. See [NOTICE](NOTICE) for policy attribution.
