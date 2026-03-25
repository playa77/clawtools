# clawtools

A collection of agent skills for OpenClaw / ClawHub. Each skill is a self-contained tool that agents can invoke via structured scripts.

## Skills

| Skill | Description |
|-------|-------------|
| [semver_engine](semver_engine/) | Deterministic semver parse/compare/bump/validate/constraint-check |
| [git_worktree](git_worktree/) | Git worktree management (list, add, remove, prune, lock, unlock) |
| [diff_analyzer](diff_analyzer/) | Structured diff analysis (files, hunks, binary detection, renames) |
| [json_schema_validator](json_schema_validator/) | JSON Schema validation and inference from data |
| [http_probe](http_probe/) | HTTP endpoint probing (status, timing, TLS, headers, redirects) |
| [man_page_reader](man_page_reader/) | Parse man pages into structured agent-friendly JSON |
| [project_manifest_reader](project_manifest_reader/) | Cross-ecosystem project manifest reader (Node, Rust, Python, Go, Java, Ruby) |

## Philosophy

Built with Rob Pike's 5 Rules of Programming:

1. Don't optimize until you've measured.
2. Measure, then optimize only what matters.
3. Fancy algorithms are slow when n is small, and n is usually small.
4. Fancy algorithms are buggier. Simple algorithms, simple data structures.
5. Data dominates. Right data structures → algorithms become self-evident.

When in doubt, use brute force. (Ken Thompson)
Write stupid code that uses smart objects. (Fred Brooks)

## License

See [LICENSE](LICENSE).
