# server-health-check — Claude Code Guidelines

## Project Overview

A lightweight Bash CLI for server health monitoring (CPU, memory, disk, load). Doubles as a learning resource for Bash scripting and Linux system administration. Single-script, zero external dependencies (uses `top`, `free`, `df`).

## Code Style

- **Bash version**: Bash 4+ only
- **ShellCheck**: Must pass `shellcheck scripts/healthcheck.sh`
- **Format**: Two-space indentation, explicit function declarations (`function_name() { ... }`)
- **Comments**: Only where the *why* is non-obvious; tutorial context lives in `docs/tutorial.md`, not inline comments
- **Error handling**: Exit early (`set -e` not used; individual checks preferred), explicit error messages to stderr

## Core Files

| File | Purpose |
|------|---------|
| `scripts/healthcheck.sh` | Main script; parse, calculate, output |
| `docs/tutorial.md` | Section-by-section walkthrough for learners |
| `tests/test_healthcheck.sh` | Simple shell-based tests (bats framework) |
| `examples/sample-output.txt` | Reference output for manual testing |

## When Adding Features

1. **Check the roadmap** — planned features are in README.md. Features not listed yet should be discussed first (YAGNI).
2. **Keep it shell-only** — no external deps, no awk/sed/Python helpers except where necessary for the core logic.
3. **Test locally** before committing: `./scripts/healthcheck.sh` and `./tests/test_healthcheck.sh`.
4. **Backward-compat**: Current output format is part of the contract; breaking changes need a migration path (e.g., a `--new-format` flag).

## Git Practices

- **Branch naming**: `feature/name`, `fix/issue`, `docs/topic`
- **Commits**: Atomic (one logical change per commit). Describe the *why*.
- **PRs**: Link to roadmap item or issue if applicable.

## Specific Guidance

- **Output format stability**: The default human-readable output (`[ OK ] CPU Usage : 12%`) should only change if there's a strong reason. New output modes (JSON, Nagios) should be *opt-in* via flags, not default.
- **Tutorial maintenance**: If you change the script's logic significantly, update `docs/tutorial.md` so learners don't read outdated code.
- **Exit codes**: Currently ignored but will matter once Nagios-style codes land (0 = OK, 1 = warning, 2 = critical).

## Roadmap Priorities

Ordered loosely by value/effort:
1. Configurable thresholds (CLI flags or config file)
2. Remote server health check via SSH (IP/hostname)
3. JSON output mode
4. Basic test suite (bats framework already present)
5. Nagios-style exit codes
6. Slack/Discord webhook alerting
7. GitHub Actions (ShellCheck CI)
8. systemd timer example

---

**Attribution**: Commits are co-authored with Claude Haiku 4.5 (noreply@anthropic.com).
