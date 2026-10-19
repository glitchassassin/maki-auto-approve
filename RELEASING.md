# Releasing

Releases for [glitchassassin/maki-auto-approve](https://github.com/glitchassassin/maki-auto-approve)
use annotated Git tags matching `VERSION`.

## Validate

```sh
lua tests/run.lua
python3 scripts/codex-prompts.py
python3 tests/integration.py
find lua plugin tests examples -name '*.lua' -exec luac -p {} \;
sh -n scripts/install-local.sh
git diff --check
```

Native tests require Maki 0.6.4 or newer, Python 3.11+, Git, and a POSIX terminal.
They use isolated XDG directories and a local fake provider, make no real model
calls, and leave normal Maki configuration unchanged. Managed-install tests make
their own temporary Git fixture, explicitly accept its install/capability prompts,
and assert the lockfile commit. The interactive fallback test explicitly approves
one pending probe in a real terminal after the model denies, including high-risk
actions with unknown authorization. Resume tests restart Maki and wake saved work
with an observation, without sending a new human message to the agent.
Native trust tests verify restricted, saved, policy-based, `/trust`, and `--trust`
configuration loading on stock Maki. No patched binary is required.

Review `CHANGELOG.md`, the global/project Lua examples, `plugin.toml`, `LICENSE`, and
`NOTICE`. The prompt check verifies upstream Git blob hashes and the generated Lua
bundle; review changes to `vendor/codex/source.json` against the intended upstream
revision when updating the baseline. Keep the README's minimum Maki version and
CI binary pin in agreement.

## Prepare the release

Choose an unused version. Update `VERSION`, the README's pinned installation
version, and `CHANGELOG.md`. Commit the validated changes and tag that commit:

```sh
release_version=$(cat VERSION)
git tag -a "v$release_version" -m "Maki Auto Approve $release_version"
```

Keep existing tags unchanged. Confirm the working tree is clean and the new tag
resolves to the intended release commit.

## Publish

Push the release commit and annotated tag to `glitchassassin/maki-auto-approve`.
Wait for the Ubuntu CI workflow to pass, then create a GitHub release from the
tag using the matching changelog entry as release notes.

Check managed installation from the repository URL and release tag in the README.
Maki's package manager installs the tagged Git contents; no separate package
archive is required.
