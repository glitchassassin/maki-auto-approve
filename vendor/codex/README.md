# Codex Guardian baseline

These files are copied verbatim from OpenAI Codex at revision
`e4568a3538c9cab6627d64ff8cdfc7d98b79b7db`, under Apache-2.0. See the repository's
`LICENSE` and `NOTICE`. `source.json` records each upstream path and Git blob hash.

- `policy_template.md`: evidence handling, authorization scoring, risk taxonomy,
  environment description, and outcome policy.
- `policy.md`: Codex's default security policy.
- `assessment.rs`: upstream output contract and parser reference; Rust is not run
  or required by this package.

`python3 scripts/codex-prompts.py` verifies the source hashes and generated Lua
bundle. `--write` regenerates that bundle without network access. Maki loads the
Lua bundle directly; there is no runtime download or prompt-file lookup.

The package substitutes the security-policy placeholder and replaces only the
template's Execution Environment section with Maki's actual capabilities and
evidence transport. The output prompt is extracted unchanged from `assessment.rs`.
The Lua response parser follows that file's optional fields, defaults, ignored
unknown fields, and recovery of a JSON object wrapped in prose.

Model/provider selection, evidence availability, bounded inspection tools, and
human fallback remain Maki integration differences. Matching the upstream policy
and response interpretation does not guarantee identical model judgments.
