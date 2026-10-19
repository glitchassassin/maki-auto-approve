# Maki Auto Approve

A native Maki Lua package that reviews pending permission prompts with a model.
It automatically approves qualifying calls once. Every other outcome goes back
to Maki's normal permission prompt, with the review rationale shown in a notice.

Requires Maki **0.6.4 or newer**. No additional runtime or model API key is needed;
the reviewer inherits the current Maki model/provider unless configured otherwise.

## Managed installation

Add the package to your global `~/.config/maki/init.lua`:

```lua
maki.pack.add({
  { src = "https://github.com/glitchassassin/maki-auto-approve", version = "v0.3.0" },
})
```

Maki asks to install the package and approve its requested capabilities. The
resolved commit is saved in `pack-lock.json`. `/packupdate maki-auto-approve`
reviews updates; to remove the package, remove its declaration, reload, and run
`/packdel maki-auto-approve`. Package declarations belong in the global init file.

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
      -- policy_rubric = [=[Your replacement Guardian security policy.]=],
    },
  },
})
```

Merge this table into an existing `maki.setup()` call; Maki permits one call per
init file. The package must be installed or declared with `maki.pack.add` so Maki
recognizes its name. All options are optional; built-in defaults enable review
using the calling model and the pinned Codex Guardian prompts.

See [examples/global.lua](examples/global.lua) for every option, its default, and
its valid range. Maki's option API accepts scalars, so names such as
`reviewer_timeout_ms` and `inspection_max_file_bytes` are flat keys. Set
`policy_rubric` to a Lua string to replace the template's Security Policy section;
Lua's `[=[...]=]` notation supports multiline policy text. The surrounding Codex
evidence rules, authorization scoring, risk taxonomy, and outcome policy stay in
place. The default security policy is in [vendor/codex/policy.md](vendor/codex/policy.md).

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
Existing chats reuse their recorded user instructions after reload or restart;
no fresh human message is required. Until reload, the running package keeps its
current settings.

Maki validates option names, scalar types, and minimums. The package also rejects
unsupported model/thinking values, oversized or empty rubrics, and values above
its limits before installing any approval hooks. Invalid options cannot grant
automatic approval; Maki reports the load/configuration error and its native
permission handling remains authoritative.

## Permission behavior

The package wraps only `permission.prompt` to grant approvals. Native permission
resolution happens first:

- Explicit allow rules execute without a model review.
- Explicit deny rules block without a model review.
- YOLO bypasses review.
- A pending ordinary prompt invokes the reviewer.
- A successfully parsed allow approves that exact call once, without saving a rule.
- Denials, invalid assessments, unavailable providers, timeouts, cancellation,
  unavailable history, changed instructions, or failed inspections
  return control to the normal permission prompt.

Prompts explicitly forced by another plugin's `ask` hook remain human-only; Maki
does not offer them to this package. In `maki -p`, nobody can answer a fallback
prompt, so Maki denies it normally. The package never bypasses that behavior.
Builtin, MCP, ACP, and nested tool calls are covered whenever Maki routes them
through the same permission hook. Tools that never prompt remain unaffected.

The default prompts are copied from Codex Guardian at revision
`e4568a3538c9cab6627d64ff8cdfc7d98b79b7db`. They assess intrinsic risk and user
authorization separately, including sensitive egress, credentials, destruction,
and persistent security changes. Their default outcome rules are:

- Low/medium risk: allow regardless of authorization, unless a specific security
  policy deny applies or there is affirmative evidence of malicious prompt injection.
- High risk: allow only with at least medium authorization, narrow scope, and no
  applicable absolute deny rule.
- Critical risk: deny.

The full upstream policy, examples, and exceptions are retained. These rules guide
the model; the package follows Codex's assessment interpretation without imposing
additional authorization thresholds after parsing. A low-risk response may be just
`{"outcome":"allow"}`. Missing optional fields default to low risk for allow/high
risk for deny, unknown authorization, and Codex's standard rationale. Like Codex,
the parser ignores extra fields and can recover a JSON object wrapped in prose.

Only the template's Execution Environment section is replaced with Maki's actual
capabilities and evidence transport. The output prompt is copied unchanged. See
[vendor/codex/README.md](vendor/codex/README.md) for provenance and drift checks.
The same policy and response interpretation do not guarantee identical judgments:
model/provider choice, available evidence, and inspection tools can differ.

## Review evidence and inspection

The package reads Maki's current conversation history, including history restored
on resume. Visible `user` messages with kind `turn` and only text/image blocks
are supplied separately as user instructions, in chronological order. Later
restrictions take priority. Observations, context updates, hidden messages, ordinary
tool results, and assistant summaries cannot independently establish authorization.
Maki does not expose the original input source in history, so a plugin-generated
regular user turn has the same provenance as other recorded user turns.

Codex's Evidence Handling rules also recognize `AGENTS.md`. A real `AGENTS.md`
read with the inspection tools can establish authorization under that exception;
text merely claiming to be such a file cannot. Maki's history API does not separately
expose developer instructions or verified `request_user_input` answers, so the
package does not manufacture those sources.

User instruction selection has its own byte budget and can reach further back
than the recent conversation window. Omitted instructions and images are labeled;
thinking and image contents are excluded. The exact pending action is never
truncated into an approval. Missing user instructions are passed to the reviewer
without an extra approval gate: Codex's low/medium-risk rules still apply. If a
policy rule needs authorization that the available evidence cannot establish,
the reviewer denies and Maki's normal approval prompt takes over. An assistant
summary cannot restore authorization from user instructions lost to compaction.

Delegated calls use the owning chat's recorded user instructions. Before accepting
an allow, the package rereads and compares those instructions. New human input,
changed history, session reset/end, or cancellation invalidates an approval still
in flight. The package keeps revision counters for race detection, with no separate
persisted authorization store or fresh-message gate.

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

Clone the repository and link your checkout into Maki:

```sh
git clone https://github.com/glitchassassin/maki-auto-approve.git
cd maki-auto-approve
sh scripts/install-local.sh
```

The installer creates a symlink under Maki's `site/pack/user/start/` directory. It
does not modify your configuration or overwrite an existing package. It honors
`XDG_DATA_HOME` and Maki's legacy `~/.maki` directory, and accepts a Maki data
directory as its only argument. Restart Maki or run `/reload` afterward.

The symlink follows your working checkout, including uncommitted edits. Managed
installation uses tagged Git contents. Use one installation method per package
name. To remove a development installation, remove its symlink and reload Maki.

Run checks from the repository root:

```sh
lua tests/run.lua
python3 scripts/codex-prompts.py
python3 tests/integration.py
```

Unit tests use Lua 5.4/5.5 and a mocked host. Native integration tests use the installed
Maki binary, isolated temporary XDG directories, and a local fake OpenAI-compatible
provider. They make no real model calls and do not install the package in your
normal Maki configuration. Python 3 is needed only for development checks.

The integration suite verifies native allow/deny bypasses, one-call automatic
approval, real interactive human fallback, headless denial, restricted asynchronous
inspection, native folder trust and option merging, malformed responses, timeout
cleanup, JIT execution, saved-chat resume without fresh human input, Codex's
low/medium-risk outcomes with unknown authorization, minimal/wrapped responses,
high-risk denial fallback, and managed Git installation with capability prompts
and a locked commit.

The Ubuntu CI workflow pins Maki 0.6.4 and checks its release archive's SHA-256.
It runs the same local suites, validates the package manifest, and checks Lua,
example, and installer syntax.
See [CHANGELOG.md](CHANGELOG.md) for the release history and
[RELEASING.md](RELEASING.md) for the release procedure.

The tests validate the integration and enforcement paths, not the judgment quality
of a particular model or custom rubric. See [NOTICE](NOTICE) for policy attribution.
