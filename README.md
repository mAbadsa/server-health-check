# server-health-check

A lightweight Bash CLI for monitoring server health (CPU, memory, disk, load) — built for quick integration into monitoring pipelines, cron jobs, and systemd timers.

![Shell](https://img.shields.io/badge/shell-bash-1f425f.svg)
![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Status](https://img.shields.io/badge/status-in%20progress-yellow.svg)

## Why this exists

Most servers need *some* form of basic health monitoring, but pulling in a full stack like Prometheus/Grafana is overkill for a small box or a quick diagnostic check. `server-health-check` is a single dependency-light script that reports on the core metrics (CPU, memory, disk, and more to come) in a format that's readable at a glance and scriptable when you need it to be.

This project also doubles as a tutorial — the `docs/tutorial.md` walks through how the script works, section by section, for anyone learning Bash scripting or basic Linux system monitoring.

## Features

- ✅ CPU, memory, and disk usage checks
- ✅ Human-readable terminal output
- 🚧 Configurable warning/critical thresholds
- 🚧 JSON output mode (for piping into other tools)
- 🚧 Nagios-style exit codes (0 = OK, 1 = warning, 2 = critical)
- 🚧 Alerting via webhook (Slack/Discord)
- 🚧 ShellCheck CI on every push

*(✅ = done, 🚧 = planned — see [Roadmap](#roadmap))*

## Quick start

```bash
git clone https://github.com/mAbadsa/server-health-check.git
cd server-health-check
chmod +x scripts/healthcheck.sh
./scripts/healthcheck.sh
```

## Sample output

```
$ ./scripts/healthcheck.sh
[ OK ]  CPU Usage      : 12%
[ OK ]  Memory Usage   : 43% (3.4G / 7.8G)
[WARN]  Disk Usage     : 81% (/dev/sda1)
```

## Usage

```bash
./scripts/healthcheck.sh [options]

Options:
  -h, --help      Show help message
```

*(More flags — thresholds, JSON output, alerting — will be documented here as they're implemented.)*

## Tutorial

If you're learning Bash or want to understand how this script works under the hood, see [`docs/tutorial.md`](docs/tutorial.md) for a walkthrough of each section.

## Roadmap

- [ ] Configurable thresholds via config file / CLI flags
- [ ] JSON output mode
- [ ] Nagios-style exit codes
- [ ] Webhook alerting (Slack/Discord)
- [ ] Basic test suite (bats)
- [ ] GitHub Actions workflow (ShellCheck)
- [ ] Docker support
- [ ] systemd timer / cron example

## Requirements

- Bash 4+
- Standard Linux utilities (`top`, `free`, `df`) — no external dependencies

## Contributing

This is currently a learning/portfolio project, but suggestions and issues are welcome.

## License

MIT — see [LICENSE](LICENSE)
