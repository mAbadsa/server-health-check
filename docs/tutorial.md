# Tutorial: Understanding `healthcheck.sh`

This guide walks through how the health check script works, section by section. It's designed for anyone learning Bash scripting or Linux system monitoring.

## Overview

The `healthcheck.sh` script monitors three core server metrics:
- **CPU Usage**: Percentage of CPU in active use
- **Memory Usage**: Percentage of RAM in use
- **Disk Usage**: Percentage of root filesystem (`/`) used

Each metric is compared against configurable **warning** and **critical** thresholds. The output uses a status label (`[ OK ]`, `[WARN]`, `[CRIT]`) to indicate how the server is doing.

## Part 1: Default Thresholds

```bash
CPU_WARN=70
CPU_CRIT=90
MEM_WARN=70
MEM_CRIT=90
DISK_WARN=80
DISK_CRIT=90
```

These variables store the default thresholds. For example, if CPU usage reaches 70%, the script marks it as `[WARN]`. At 90%, it's `[CRIT]`. You can override these with command-line flags.

## Part 2: Command-Line Flag Parsing

```bash
while [[ $# -gt 0 ]]; do
  case "$1" in
    --cpu-warn)
      CPU_WARN="$2"
      shift 2
      ;;
    ...
  esac
done
```

This loop reads arguments from the command line. Each `--flag value` pair updates the corresponding threshold.

**Example usage:**
```bash
./healthcheck.sh --cpu-warn 80 --cpu-crit 95
```

Here, `$1` is `--cpu-warn`, `$2` is `80`. The `shift 2` removes both from the argument list so the loop can process the next pair.

## Part 3: Input Validation

```bash
validate_threshold() {
  local name="$1" warn="$2" crit="$3"
  
  if ! [[ "$warn" =~ ^[0-9]+$ ]] || (( warn < 0 || warn > 100 )); then
    echo "Error: $name warn must be an integer 0-100, got '$warn'" >&2
    exit 2
  fi
  
  if (( warn >= crit )); then
    echo "Error: $name warn ($warn) must be less than crit ($crit)" >&2
    exit 2
  fi
}
```

This function checks three things:
1. The value is a valid integer (regex match: `^[0-9]+$`)
2. The value is within the valid range (0–100)
3. **Warning is strictly less than critical** — it doesn't make sense to warn at a higher level than you declare critical

**Example invalid input:**
```bash
./healthcheck.sh --cpu-warn 95 --cpu-crit 90
# Error: CPU warn (95) must be less than crit (90)
# Exits with code 2 (usage error)
```

## Part 4: Status Determination

```bash
status_for() {
  local value="$1" warn="$2" crit="$3"
  
  if (( value >= crit )); then
    echo "CRIT"
  elif (( value >= warn )); then
    echo "WARN"
  else
    echo "OK"
  fi
}
```

This helper compares a metric value against thresholds and returns the status. The logic is simple:
- If value ≥ critical threshold → `CRIT`
- Else if value ≥ warning threshold → `WARN`
- Else → `OK`

**Why `>=` instead of `>`?** If your threshold says "warn at 70%", you want 70% to be a warning, not still OK.

## Part 5: Metric Collection

### CPU Usage
```bash
get_cpu() {
  top -bn1 | grep "Cpu(s)" | awk '{printf "%.0f\n", $2}'
}
```

This reads the `top` command's first snapshot (`-bn1`), extracts the CPU usage line, and parses out the user CPU percentage from field `$2` (e.g., "12.5%us,"). The `awk` expression coerces the string to a number (stops at the `%` sign) and rounds it to a whole number.

*Note: This captures user CPU only. To measure total CPU (including system, IO-wait, etc.), you'd use `vmstat 1 2 | tail -1 | awk '{print 100 - $15}'`, but this adds a 2-second latency.*

### Memory Usage
```bash
get_mem() {
  free | grep Mem | awk '{printf "%.0f\n", ($3 / $2) * 100}'
}
```

The `free` command shows memory in lines. We extract the `Mem` line, divide used (`$3`) by total (`$2`), multiply by 100 to get percent, and round.

### Disk Usage
```bash
get_disk() {
  df -P / | tail -1 | awk '{print $5+0}'
}
```

The `df -P /` command shows filesystem info in POSIX format (one line per filesystem, no wrapping). We take the last line (the actual filesystem), extract the usage percentage column (`$5`), and add 0 to convert the string (e.g., "75%") to a pure number.

## Part 6: Output Formatting

```bash
format_line() {
  local status="$1" label="$2" value="$3" extra="$4"
  printf "[%-4s]  %-14s: %s%s\n" "$status" "$label" "$value" "$extra"
}
```

This helper prints a single status line. The `printf` format:
- `[%-4s]` — left-aligned status in brackets (e.g., `[ OK ]`)
- `%-14s` — left-aligned label padded to 14 characters (for alignment)
- `%s%s` — the value and optional extra info

**Output example:**
```
[ OK ]  CPU Usage      : 12%
[WARN]  Memory Usage   : 75%
[CRIT]  Disk Usage     : 92%
```

## Part 7: The Main Flow

```bash
main() {
  local cpu mem disk
  local cpu_status mem_status disk_status
  
  cpu=$(get_cpu)
  mem=$(get_mem)
  disk=$(get_disk)
  
  cpu_status=$(status_for "$cpu" "$CPU_WARN" "$CPU_CRIT")
  mem_status=$(status_for "$mem" "$MEM_WARN" "$MEM_CRIT")
  disk_status=$(status_for "$disk" "$DISK_WARN" "$DISK_CRIT")
  
  format_line "$cpu_status" "CPU Usage" "${cpu}%"
  format_line "$mem_status" "Memory Usage" "${mem}%"
  format_line "$disk_status" "Disk Usage" "${disk}%"
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && main
```

The `main` function:
1. Calls each `get_*` function to collect metrics
2. Calls `status_for` to compare them against thresholds
3. Formats and prints each line

The last line is a guard: `[[ "${BASH_SOURCE[0]}" == "$0" ]]` checks if this script is being run directly (true) or sourced by a test file (false). This allows the test suite to import functions without running `main`.

## How It All Fits Together

1. User runs: `./healthcheck.sh --mem-warn 60 --mem-crit 85`
2. Script parses flags and updates `MEM_WARN=60`, `MEM_CRIT=85`
3. Script validates: is 60 < 85? Yes. Both 0–100? Yes. ✓
4. `main()` collects memory usage (e.g., 72%)
5. `status_for 72 60 85` returns `WARN` (72 ≥ 60, but < 85)
6. Script prints: `[WARN]  Memory Usage   : 72%`

## Part 8: Remote Execution via SSH

The script can run on a remote host via SSH:

```bash
./scripts/healthcheck.sh --host 192.168.1.10
./scripts/healthcheck.sh --host app@server.example.com --cpu-warn 80
```

### How Remote Mode Works

1. The `--host` flag sets `REMOTE_MODE=1` and `HOST="..."` during flag parsing.
2. The forward array `FWD=()` collects all threshold flags to send to the remote.
3. At the end, the guard checks: if `REMOTE_MODE` is set, call `run_remote()` instead of `main()`.
4. `run_remote()` validates the host (rejects option injection like `-oProxyCommand=...`).
5. It runs: `ssh -o BatchMode=yes -o ConnectTimeout=5 "$host" bash -s "${FWD[@]}" < "$0"`
   - `BatchMode=yes` = key-only auth, never prompt for password (safe in cron)
   - `ConnectTimeout=5` = give up after 5 seconds if unreachable
   - `bash -s` = read the script from stdin
   - `"${FWD[@]}"` = forward the threshold flags as arguments
   - `< "$0"` = pipe the script itself to the remote bash

### Why Pipe the Script?

This avoids having to install the script on every remote server. Just run it once with `--host`, and it uses SSH to send the script + flags to the remote bash. The remote side parses flags and collects metrics just like the local version.

### SSH Requirements

- Remote host must have bash and `top`/`free`/`df` (standard on Linux)
- SSH key auth required (no password prompts; set `~/.ssh/config` for port/identity)
- Error handling: if SSH fails, the script exits with code 2

### Validation

The script validates the host to prevent injection attacks:
- Must match `^[A-Za-z0-9._@:-]+$` (alphanumeric, dots, underscores, @, hyphens, colons)
- Cannot start with `-` (blocks `-oProxyCommand=...` attacks)
- Must not be empty

## Testing

The `tests/test_healthcheck.sh` file contains simple assertions:
```bash
assert "OK" "$(status_for 30 70 90)" "status_for: 30% with warn=70, crit=90 → OK"
```

Run tests with: `bash tests/test_healthcheck.sh`

Tests verify:
- `status_for` logic at boundary values (warn, crit, between)
- Invalid input rejection (non-numeric, out of range, warn ≥ crit)
- Exit codes (0 for success, 2 for usage errors)
