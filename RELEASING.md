# Releasing

The prepared version is in `VERSION`. This repository can be tested, committed,
and tagged entirely locally. A GitHub repository or release is not required.

## Validate

```sh
lua tests/run.lua
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
one pending probe in a real terminal after the model declines automatic approval.
Native trust tests verify restricted, saved, policy-based, `/trust`, and `--trust`
configuration loading on stock Maki. No patched binary is required.

Review `CHANGELOG.md`, the global/project Lua examples, `plugin.toml`, `LICENSE`, and
`NOTICE`. Keep the README's minimum Maki version and CI binary pin in agreement.
The `OWNER` URL in the README is intentionally a placeholder until a public
repository is selected; replace it with the actual URL before publishing.

## Prepare a local version

Make an ordinary release commit after validation and tag that exact commit:

```sh
git tag -a v0.2.0 -m "Maki Auto Approve 0.2.0"
```

An existing tag must never be silently moved. Check that the working tree is
clean and the tag resolves to the intended release commit. The package manager
can install this tag using the repository's local absolute path.

## Publication is a separate action

Creating a remote repository, adding a publishing remote, pushing commits/tags,
or creating a hosted release requires an explicit request. None of the validation
scripts, installer, or CI workflow publishes artifacts, pushes tags, or creates
releases. Once a public repository is selected and publishing is authorized,
update the README URL, rerun validation, and follow that repository's release policy.
