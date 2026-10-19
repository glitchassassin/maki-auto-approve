# Changelog

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
