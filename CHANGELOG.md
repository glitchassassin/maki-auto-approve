# Changelog

## 0.2.0 — 2026-10-19

- Configure the installed package through `plugins["maki-auto-approve"]` in Maki's
  global and project `init.lua`, including the rubric and all reviewer limits.
- Inherit Maki's native folder trust and per-option merging. Trusted project
  settings override global values; untrusted project settings are skipped.
- Remove TOML policy files, the custom parser, plugin-specific trust commands,
  and the separate consent store. Native `enabled` controls the package.
- Apply settings through Maki's normal reload/restart lifecycle, with documented
  migration and Lua examples. Keep final authorization/cancellation checks after
  asynchronous inspection validation.
- Test native trust grants, untrusted fallback to global settings, custom rubrics,
  native package toggles, and managed installation on stock Maki 0.6.4.

## 0.1.0 — 2026-10-19

- Review only ordinary pending Maki permission prompts. Native allow, deny, YOLO,
  and intentionally human-only decisions remain authoritative.
- Inherit the calling model by default, with optional global and trusted project
  settings in `auto-approve.toml`.
- Require explicit consent for a checkout's exact project-policy file. Changes
  invalidate that consent; untrusted policies receive normal human prompts.
- Return model denials, errors, timeouts, uncertainty, or stale evidence to the
  normal permission prompt. Validate authorization after all asynchronous reads.
- Offer three bounded read-only inspection tools and in-memory review history.
- Include a Codex-derived rubric, Apache-2.0 attribution, managed/local installation
  instructions, regression tests, native terminal tests, and pinned Ubuntu CI.
