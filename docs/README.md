# Documentation

Maki Auto Approve reviews ordinary pending tool calls with a model, allowing
qualifying calls once and returning other decisions to Maki's permission prompt.

If you are new to Maki, first follow its [quick start](https://maki.sh/docs/quick-start/)
to install it and connect a model provider. Then use these guides:

- [Installation](installation.md): prerequisites, required permissions and their
  rationale, managed installation, verification, updates, removal, and troubleshooting.
- [Configuration](configuration.md): global and project settings, every option,
  folder trust, custom security policies, reload, and disabling reviews.
- [Approval policy](approval-policy.md): which calls get reviewed, risk and
  authorization rules, evidence, inspection tools, security limits, and history.
- [Design decisions](design.md): why the plugin uses native permissions and trust,
  one-call approvals, Codex Guardian prompts, and restricted inspection.
- [Development](development.md): local checkout setup, repository layout, test
  coverage, and prompt maintenance.
- [Releasing](releasing.md): validation, versioning, tags, and publication.

The [global](../examples/global.lua) and [project](../examples/project.lua) Lua
examples are ready to adapt. [Codex provenance](../vendor/codex/README.md),
[NOTICE](../NOTICE), and [LICENSE](../LICENSE) document policy attribution.
See the [changelog](../CHANGELOG.md) for release history.

[Back to the project README](../README.md)
