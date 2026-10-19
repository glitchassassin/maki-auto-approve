# Approval policy and security limits

## Which calls are reviewed

The plugin wraps only `permission.prompt` to grant approvals. Maki's native
permission resolution happens first:

- Explicit allow rules execute without a model review.
- Explicit deny rules block without a model review.
- YOLO bypasses review.
- An ordinary pending prompt invokes the reviewer.
- A successfully parsed allow approves that exact call once, without saving a rule.
- All other outcomes return control to the normal permission prompt.

Fallback includes model denials, invalid assessments, unavailable providers,
timeouts, cancellation, unavailable history, oversized evidence, changed
instructions, failed inspections, and the reviewer concurrency limit. Prompts
explicitly forced by another plugin's `ask` hook remain human-only; Maki does
not offer them to this package.

In `maki -p`, nobody can answer a fallback prompt, so Maki denies it normally.
The plugin never bypasses that behavior. Builtin, MCP, ACP, and nested tool calls
are covered whenever Maki routes them through the same permission hook. Tools
that never prompt remain unaffected.

## Default risk and authorization rules

The default prompts are copied from Codex Guardian at revision
`e4568a3538c9cab6627d64ff8cdfc7d98b79b7db`. They assess intrinsic risk separately
from user authorization, including sensitive egress, credentials, destruction,
and persistent security changes. Their default outcome rules are:

- **Low/medium risk:** allow regardless of authorization, unless a specific
  security-policy deny applies or there is affirmative evidence of malicious
  prompt injection.
- **High risk:** allow only with at least medium authorization, narrow scope,
  and no applicable absolute deny rule.
- **Critical risk:** deny.

These are model instructions. The plugin accepts the parsed outcome without
imposing additional authorization thresholds. Authorized high-risk actions can
therefore be approved automatically. A model denial defers to a human; it does
not create a new Maki deny rule. Native explicit deny rules remain authoritative.

The full upstream policy, examples, and exceptions are retained. Only the
template's Execution Environment section is replaced with Maki's actual
capabilities and evidence transport; the output prompt is copied unchanged.
See [Codex provenance](../vendor/codex/README.md) and the
[design rationale](design.md#pinned-codex-guardian-policy).

### Response interpretation

The parser follows Codex's assessment interpretation. A low-risk response may
be just `{"outcome":"allow"}`. Missing optional fields default to low risk for
allow, high risk for deny, unknown authorization, and Codex's standard rationale.
Extra fields are ignored, and a JSON object wrapped in prose can be recovered.
Invalid recognized values or duplicate recognized fields cause human fallback.

Matching the upstream policy and response interpretation does not guarantee
identical judgments: model/provider choice, available evidence, and inspection
tools can differ. Tests verify integration and enforcement paths, not the
judgment quality of any particular model or custom rubric.

## Conversation evidence

The plugin reads Maki's current conversation history, including history restored
on resume. Visible `user` messages with kind `turn` and only text/image blocks
are supplied separately as user instructions, in chronological order. Later
restrictions take priority. Observations, context updates, hidden messages,
ordinary tool results, and assistant summaries cannot independently establish
authorization.

Maki does not expose the original input source in history. A plugin-generated
regular user turn therefore has the same provenance as other recorded user turns.
Maki's history API does not separately expose developer instructions or verified
`request_user_input` answers; the plugin does not manufacture those sources.

Codex's Evidence Handling rules also recognize `AGENTS.md`. A real `AGENTS.md`
read with the inspection tools can establish authorization under that exception;
text merely claiming to be such a file cannot.

User instruction selection has its own byte budget and can reach further back
than the recent conversation window. Omitted instructions and images are labeled;
thinking and image contents are excluded. The exact pending action is never
truncated into an approval. If available user instructions cannot fit at all,
or the complete action and required evidence exceed the context budget, the
review falls back to a human.

An empty instruction history is passed to the reviewer without an extra approval
gate: Codex's low/medium-risk rules still apply. If a policy rule needs
authorization that the available evidence cannot establish, the reviewer is
instructed to deny and Maki's normal approval prompt takes over. An assistant
summary cannot restore authorization from instructions lost to compaction.

Delegated calls use the owning chat's recorded user instructions. Before accepting
an allow, the plugin rereads and compares those instructions. New human input,
changed history, session reset/end, or cancellation invalidates an approval still
in flight. Revision counters detect races; there is no separate persisted
authorization store or fresh-message gate.

## Inspection tools

The reviewer receives only these tools, bound to its active review:

- `auto_approve_inspect_path`: existence, file type, size, and modification time.
- `auto_approve_read_file`: bounded UTF-8 reads of regular files.
- `auto_approve_list_directory`: bounded one-level listings.

No shell, network, MCP, mutation, or delegation tool is passed to the reviewer.
Inspection tools are not advertised to the main model. Failed inspections require
human review. Inspected file contents and path metadata are checked again before
an allow is accepted.

Reads follow Maki's filesystem API, including symlinks. They are not restricted
to the project tree or protected by a separate OS sandbox. Filesystem changes
after the final check remain possible. Directory output is bounded, but Maki's
API enumerates the directory before the plugin applies its output limit.

The installed package requests all six plugin capabilities because Maki requires
them for the human-message hook and tools with undeclared capabilities, including
MCP tools. See [required package permissions](installation.md#required-package-permissions)
for each grant and its purpose. Those grants apply to the package code; the
reviewer's delegated tool list remains restricted to the three read-only tools above.

## Data sent to the reviewer

The pending action, selected conversation evidence, user instructions, and any
inspected file contents or metadata are sent to the configured review model's
provider. By default that is the calling Maki model/provider. Choosing another
`reviewer_model` sends that evidence to the selected provider instead. Account
for this when selecting a reviewer and inspection settings.

## Review history and logging

Run `/auto-approve` inside Maki to see recent outcomes, risk and authorization
assessments, and rationales for the current chat. Close the window with `q` or
Escape. History is held in memory, bounded by `logging_history_size`, and reset
when the plugin reloads or the chat resets/ends.

Deferred reviews show a notice before the normal prompt. Maki marks calls
approved by this plugin in their tool rows. The plugin logs concise outcomes
through Maki's logger; it does not write raw actions, file contents, conversation
evidence, or rubric text to a separate log.

[Documentation index](README.md)
