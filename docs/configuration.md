# Configuration

All options are optional. Without overrides, reviews inherit the calling
model/provider and thinking setting, use the pinned Codex Guardian security
policy, and time out after 45 seconds.

## Global settings

Configure the installed or declared package in your global
`~/.config/maki/init.lua`:

```lua
maki.setup({
  plugins = {
    ["maki-auto-approve"] = {
      reviewer_model = "", -- Inherit the calling model/provider.
      reviewer_timeout_ms = 45000,
      inspection_max_file_bytes = 65536,
    },
  },
})
```

Merge the `plugins` entry into an existing `maki.setup()` call; Maki permits only
one call per init file. The package must be installed or declared with
`maki.pack.add` so Maki recognizes its name. See
[installation](installation.md#install-a-release) for the declaration and
[Maki's configuration reference](https://maki.sh/docs/configuration/) for the host
configuration lifecycle.

Maki's option API accepts scalars. Use flat keys such as `reviewer_timeout_ms`,
rather than nested reviewer tables. The [global example](../examples/global.lua)
contains all settings and defaults.

## Option reference

All numeric options require integers. Byte limits count bytes, not characters.
`enabled` is Maki's native package toggle; the remaining options are registered
by this plugin.

| Option | Default | Accepted values and purpose |
| --- | --- | --- |
| `enabled` | `true` | Boolean; `false` disables the package. |
| `reviewer_model` | `""` | Empty inherits; otherwise a `provider/model-id` string for a model available in Maki. |
| `reviewer_thinking` | `""` | Empty inherits; `off`, `minimal`, `low`, `medium`, `high`, `xhigh`, `max`, or `adaptive`. The chosen model must support the setting. |
| `reviewer_timeout_ms` | `45000` | `100`–`55000`; review deadline within Maki's 60-second hook window. |
| `reviewer_max_inspections` | `8` | `1`–`32`; inspection calls per review. |
| `reviewer_max_concurrent` | `2` | `1`–`8`; concurrent reviews; excess calls fall back to human approval. |
| `context_max_messages` | `40` | `1`–`200`; recent conversation messages included as evidence. |
| `context_max_bytes` | `48000` | `2048`–`200000`; total review context budget, including the action and user instructions. |
| `context_max_user_bytes` | `16000` | `512`–`64000`; separate budget for recorded user instructions from available history. |
| `inspection_enabled` | `true` | Boolean; offer the reviewer bounded read-only inspection tools. |
| `inspection_max_file_bytes` | `65536` | `256`–`262144`; maximum bytes per inspected UTF-8 regular file. |
| `inspection_max_directory_entries` | `100` | `1`–`1000`; output entries per one-level directory listing. |
| `logging_history_size` | `50` | `1`–`200`; review outcomes retained in memory per chat. |
| `policy_rubric` | [Bundled security policy](../vendor/codex/policy.md) | Nonblank Lua string, at most `64000` bytes; replaces only the Security Policy section. |

Changing `reviewer_model` uses another provider/model already available to Maki;
it does not configure provider credentials. Empty strings restore inheritance
for the model and thinking options. Lower timeouts, smaller evidence budgets,
and tighter inspection limits can increase human fallback. Setting
`inspection_enabled = false` removes inspection tools; the reviewer still
receives conversation evidence and the pending action.

## Project settings and folder trust

Add overrides to `<project>/.maki/init.lua`:

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

Maki merges the global options with those from the project configuration it
loads. Omitted project options inherit global values; an explicitly supplied
string replaces the global string. See the
[project example](../examples/project.lua).

Project configuration follows [Maki's folder trust](https://maki.sh/docs/folder-trust/).
When Maki skips an untrusted project's `init.lua`, the plugin continues using
global settings and built-in defaults. This includes the reviewer model, policy,
limits, and `enabled` toggle: an untrusted project's `enabled = false` is skipped
along with its other settings.

Use Maki's normal `/trust`, `maki trust add`, trust-path policy, or one-run
`--trust` grant when appropriate. There are no plugin-specific trust prompts,
commands, consent records, or extra project opt-in flags.

## Custom security policy

Set `policy_rubric` inside the plugin options to replace the template's Security
Policy section. Lua's `[=[...]=]` notation supports multiline text:

```lua
policy_rubric = [=[
Classify shell commands that delete project files as high risk.
Deny them unless the user explicitly authorized the specific deletion.
]=],
```

This is a replacement, so include every security rule you want to retain. Start
from the [default policy](../vendor/codex/policy.md) when adapting it. The
surrounding Codex evidence rules, authorization scoring, risk taxonomy, and
outcome policy remain in place. See [approval policy](approval-policy.md) and
[design rationale](design.md#pinned-codex-guardian-policy) for their scope.

## Disable reviews

Set `enabled = false` under `plugins["maki-auto-approve"]` in global or trusted
project configuration, then reload. Maki will use its normal permission handling.
Set it to `true` or remove that override to re-enable the plugin. This is a native
package option, so it prevents the plugin from loading, including `/auto-approve`.

## Reload and validation

Run `/reload` inside Maki or restart after editing settings. Native reload
rebuilds package options and hooks; until then, the running plugin keeps its
current settings. Existing chats reuse recorded user instructions after reload
or restart, so no fresh human message is required.

Maki validates option names, scalar types, and minimums. The plugin also rejects
unsupported model/thinking values, oversized or blank rubrics, and values above
its limits before installing any approval hooks. Invalid settings produce a
load/configuration error; they cannot grant automatic approval. Maki's native
permission handling remains authoritative.

[Documentation index](README.md)
