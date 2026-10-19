# Design decisions

These choices keep automatic review integrated with Maki's permission system
and make the policy baseline reproducible.

## Native permission handling and one-call approvals

The plugin grants approvals only through `permission.prompt`, after Maki has
resolved native allow/deny rules and YOLO behavior. This preserves explicit user
rules and prompts intentionally reserved for a human by another plugin.

An allow applies only to the pending call. It never saves a permission rule,
because a judgment about one action and its evidence does not establish approval
for future actions. A denial, failure, or stale review returns to Maki's normal
prompt so the user retains the final decision. Headless fallback uses Maki's
normal denial behavior. See [approval flow](approval-policy.md#which-calls-are-reviewed).

## Native configuration and folder trust

Global and project `init.lua` settings use Maki's option registration, merging,
reload lifecycle, and `enabled` toggle. This avoids a second configuration
format, trust prompt, or consent database. Maki decides whether a project's
configuration is trusted and loaded; the plugin receives the resulting options.

Options are flat scalars because that is what Maki's package option API accepts.
Validation runs before approval hooks are installed, so a configuration error
cannot enable reviews with partially accepted settings. See
[configuration](configuration.md).

## Pinned Codex Guardian policy

The plugin bundles a specific Codex Guardian revision as its default policy and
preserves the upstream evidence handling, risk taxonomy, authorization scoring,
outcome rules, and response interpretation. This provides an auditable baseline
whose source hashes and generated Lua bundle can be checked without a network
request. There is no runtime policy download.

Only the Execution Environment section changes to describe Maki's actual
capabilities and evidence transport. A custom `policy_rubric` replaces the Security
Policy section while retaining the surrounding assessment framework. The plugin
does not add a separate authorization threshold after parsing, which preserves
the upstream low/medium-risk rules and minimal allow responses.

This is policy compatibility, not a guarantee of matching model judgments. Maki
can supply different models, evidence, and inspection tools. See
[default rules](approval-policy.md#default-risk-and-authorization-rules) and
[upstream provenance](../vendor/codex/README.md).

## Recorded instructions and bounded evidence

Maki's recorded user turns survive reload, restart, and saved-chat resume, so the
plugin uses them rather than requiring a fresh message or persisting a separate
authorization store. Instructions are separated from ordinary conversation
evidence so tool output and assistant summaries cannot grant authorization.
Their separate byte budget can retain instructions older than the recent
conversation window.

Budget limits bound review input, and omission markers expose missing evidence.
The pending action must fit in full; truncating it could hide the part that
changes its risk. Instructions and inspected files are checked again before an
allow, with final cancellation and revision checks after asynchronous reads.
This reduces stale approvals while retaining the
[documented provenance and filesystem limits](approval-policy.md#conversation-evidence).

## Restricted tools and broad package capabilities

The reviewer can inspect paths, read files, and list directories to resolve
uncertainty about the action. Giving it only these bounded read tools prevents
it from executing commands or changing the state it is evaluating. The tools
are bound to an active review and withheld from the main model.

The package itself requests all six Maki capabilities to wrap tools whose
capabilities are undeclared, including MCP tools, and to observe user messages.
The [permission reference](installation.md#required-package-permissions) lists
each grant and explains Maki's hook requirements.
Package capability grants and the reviewer's tool list serve different purposes.
Read access follows Maki's filesystem API and is not an OS sandbox. See
[inspection limits](approval-policy.md#inspection-tools).

## Model inheritance and resource limits

Inheriting the calling model/provider lets an existing Maki setup work without
another account or credential. An explicit reviewer model supports a different
cost, latency, or judgment tradeoff. Conversation and inspection evidence goes
to whichever provider reviews the call.

The timeout covers queuing and review within Maki's hook window. When all review
slots are occupied, new calls wait in FIFO order. Slots are reserved before
asynchronous context reads so simultaneous arrivals cannot exceed the limit.
Cancellation removes pending waiters and releases held slots; expiry returns
to normal human approval. Input and inspection limits bound the work a review
can do. The [configuration reference](configuration.md#option-reference)
lists the defaults and supported ranges.

[Documentation index](README.md)
