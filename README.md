# clawtools

A collection of agent skills for OpenClaw / ClawHub. Each skill is a self-contained tool that agents can invoke via structured scripts.

## Skills

| Skill | Description |
|-------|-------------|
| [semver_engine](semver_engine/) | Deterministic semver parse/compare/bump/validate/constraint-check |

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
