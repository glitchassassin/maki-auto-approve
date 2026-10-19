# Changelog

## 0.3.1 — 2026-10-19

- Document installation and development from `glitchassassin/maki-auto-approve`.
- Remove obsolete prototype migration notes and document the maintainer release process.

## 0.3.0 — 2026-10-19

- Bundle Codex Guardian's full default policy, policy template, and output contract
  from revision `e4568a3538c9cab6627d64ff8cdfc7d98b79b7db`, with verified upstream
  Git blob hashes and a reproducible Lua bundle checked in CI.
- Preserve upstream evidence, authorization, risk, and outcome guidance verbatim;
  replace only the Execution Environment section with Maki's real capabilities.
- Follow Codex's low/medium-risk authorization thresholds and assessment parsing,
  including minimal allows, optional fields, defaults, extra fields, and wrapped JSON.
- Remove the additional host authorization thresholds and empty-user-history gate.
  Keep one-call approvals, human fallback, native trust, and race protection.
- Retain `policy_rubric` as a replacement for the template's Security Policy section;
  the surrounding Codex assessment guidance remains in place.
- Correct the local installer's restart/reload guidance to reflect reuse of
  recorded user instructions, without requiring a fresh human message.

## 0.2.1 — 2026-10-19

- Use Maki's recorded user turns as authorization evidence after restart, reload,
  and chat resume. Remove the in-memory message capture and fresh-message gate.
- Keep user instructions separate from observations, tool output, hidden messages,
  and assistant summaries. Preserve instruction order and label omitted evidence.
- Require medium or high authorization for every automatic approval; low or unknown
  authorization falls back to Maki's ordinary prompt even if the model returns allow.
- Revalidate recorded user instructions before approval and retain final synchronous
  input-revision and cancellation checks after asynchronous reads.
- Test saved-chat resume in a fresh stock Maki process without new human input,
  interactive uncertainty fallback, and input/history races.

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
