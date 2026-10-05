#!/bin/bash

set -u

# Default thresholds (percent)
CPU_WARN=70
CPU_CRIT=90
MEM_WARN=70
MEM_CRIT=90
DISK_WARN=80
DISK_CRIT=90

# Remote host and mode flag
HOST=""
REMOTE_MODE=0

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --host [user@]IP       Check remote host via SSH (key auth required)
  --cpu-warn N           CPU warning threshold (0-100, default: 70)
  --cpu-crit N           CPU critical threshold (0-100, default: 90)
  --mem-warn N           Memory warning threshold (0-100, default: 70)
  --mem-crit N           Memory critical threshold (0-100, default: 90)
  --disk-warn N          Disk warning threshold (0-100, default: 80)
  --disk-crit N          Disk critical threshold (0-100, default: 90)
  -h, --help             Show this help message

Examples:
  $(basename "$0")
  $(basename "$0") --host 192.168.1.10
  $(basename "$0") --host app@server.example.com --cpu-warn 80 --cpu-crit 95
EOF
}

# Collect flags to forward to remote
FWD=()

# Parse command-line flags
while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)
      REMOTE_MODE=1
      HOST="$2"
      shift 2
      ;;
    --cpu-warn)
      CPU_WARN="$2"
      FWD+=("--cpu-warn" "$2")
      shift 2
      ;;
    --cpu-crit)
      CPU_CRIT="$2"
      FWD+=("--cpu-crit" "$2")
      shift 2
      ;;
    --mem-warn)
      MEM_WARN="$2"
      FWD+=("--mem-warn" "$2")
      shift 2
      ;;
    --mem-crit)
      MEM_CRIT="$2"
      FWD+=("--mem-crit" "$2")
      shift 2
      ;;
    --disk-warn)
      DISK_WARN="$2"
      FWD+=("--disk-warn" "$2")
      shift 2
      ;;
    --disk-crit)
      DISK_CRIT="$2"
      FWD+=("--disk-crit" "$2")
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

# Validate and run remote check
validate_host() {
  local host="$1"

  if [[ -z "$host" ]]; then
    echo "Error: --host requires a value" >&2
    exit 2
  fi

  if [[ "$host" =~ ^- ]]; then
    echo "Error: host cannot start with '-' (suspected option injection)" >&2
    exit 2
  fi

  if ! [[ "$host" =~ ^[A-Za-z0-9._@:-]+$ ]]; then
    echo "Error: invalid host format: $host" >&2
    exit 2
  fi
}

run_remote() {
  local host="$1"
  shift
  local -a fwd_args=("$@")

  validate_host "$host"

  echo "Host: $host"

  if ! HEALTHCHECK_REMOTE=1 ssh -o BatchMode=yes -o ConnectTimeout=5 "$host" bash -s "${fwd_args[@]}" < "$0"; then
    echo "Error: cannot reach $host via SSH" >&2
    exit 2
  fi
}

# Validate thresholds
validate_threshold() {
  local name="$1" warn="$2" crit="$3"

  if ! [[ "$warn" =~ ^[0-9]+$ ]] || (( warn < 0 || warn > 100 )); then
    echo "Error: $name warn must be an integer 0-100, got '$warn'" >&2
    exit 2
  fi

  if ! [[ "$crit" =~ ^[0-9]+$ ]] || (( crit < 0 || crit > 100 )); then
    echo "Error: $name crit must be an integer 0-100, got '$crit'" >&2
    exit 2
  fi

  if (( warn >= crit )); then
    echo "Error: $name warn ($warn) must be less than crit ($crit)" >&2
    exit 2
  fi
}

validate_threshold "CPU" "$CPU_WARN" "$CPU_CRIT"
validate_threshold "Memory" "$MEM_WARN" "$MEM_CRIT"
validate_threshold "Disk" "$DISK_WARN" "$DISK_CRIT"

# Return status string based on value vs thresholds
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

# Get CPU usage percentage (user CPU only; total CPU would use vmstat but adds 2s latency)
get_cpu() {
  top -bn1 | grep "Cpu(s)" | awk '{printf "%.0f\n", $2}'
}

# Get memory usage percentage
get_mem() {
  free | grep Mem | awk '{printf "%.0f\n", ($3 / $2) * 100}'
}

# Get disk usage percentage (root filesystem)
get_disk() {
  df -P / | tail -1 | awk '{print $5+0}'
}

# Format output line
format_line() {
  local status="$1" label="$2" value="$3" extra="${4:-}"
  printf "[%-4s]  %-14s: %s%s\n" "$status" "$label" "$value" "$extra"
}

# Main
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

# Guard so test file can source this script (HEALTHCHECK_REMOTE set by run_remote)
if [[ -z "${HEALTHCHECK_REMOTE:-}" ]]; then
  if (( REMOTE_MODE )); then
    run_remote "$HOST" "${FWD[@]}"
  else
    main
  fi
fi
