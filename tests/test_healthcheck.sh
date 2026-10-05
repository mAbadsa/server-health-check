#!/bin/bash

# Simple test framework: source the script and run assertion tests
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$SCRIPT_DIR/scripts/healthcheck.sh"
TEST_TMPDIR=$(mktemp -d)
trap "rm -rf '$TEST_TMPDIR'" EXIT

# Create stub ssh command that prints args and cats stdin
mkdir -p "$TEST_TMPDIR/bin"
cat > "$TEST_TMPDIR/bin/ssh" <<'STUB'
#!/bin/bash
# Stub ssh for testing: ssh -o opt val -o opt val HOST bash -s args...
if [[ "$1" == "-o" ]] && [[ "$2" == "BatchMode=yes" ]]; then
  shift 4  # Skip -o BatchMode=yes -o ConnectTimeout=5
  host="$1"
  shift    # Skip HOST

  # Simulate failure if host is unreachable
  if [[ "$host" == "10.255.255.1" ]]; then
    exit 255
  fi

  # Run: bash -s args... < stdin
  echo "Host: $host"
  "$@"
else
  echo "Unexpected ssh args: $@" >&2
  exit 1
fi
STUB
chmod +x "$TEST_TMPDIR/bin/ssh"

# Prepend stub directory to PATH so our ssh is used
export PATH="$TEST_TMPDIR/bin:$PATH"

# Source the script to test helper functions
source "$SCRIPT"

# Test counter
tests_run=0
tests_passed=0

assert() {
  local expected="$1" actual="$2" desc="$3"
  ((tests_run++))

  if [[ "$expected" == "$actual" ]]; then
    echo "✓ $desc"
    ((tests_passed++))
  else
    echo "✗ $desc (expected: '$expected', got: '$actual')"
  fi
}

assert_exit() {
  local expected_code="$1" cmd="$2" desc="$3"
  ((tests_run++))

  eval "$cmd" > /dev/null 2>&1
  local actual_code=$?

  if [[ "$expected_code" == "$actual_code" ]]; then
    echo "✓ $desc"
    ((tests_passed++))
  else
    echo "✗ $desc (expected exit code: $expected_code, got: $actual_code)"
  fi
}

echo "=== Testing status_for function ==="

# Test OK status (below warning)
assert "OK" "$(status_for 30 70 90)" "status_for: 30% with warn=70, crit=90 → OK"

# Test WARN status (at and above warning, below critical)
assert "WARN" "$(status_for 70 70 90)" "status_for: 70% with warn=70, crit=90 → WARN"
assert "WARN" "$(status_for 75 70 90)" "status_for: 75% with warn=70, crit=90 → WARN"

# Test CRIT status (at and above critical)
assert "CRIT" "$(status_for 90 70 90)" "status_for: 90% with warn=70, crit=90 → CRIT"
assert "CRIT" "$(status_for 95 70 90)" "status_for: 95% with warn=70, crit=90 → CRIT"

echo ""
echo "=== Testing threshold validation ==="

# Valid thresholds should succeed
assert_exit 0 "$SCRIPT" "script with defaults exits 0"

# Invalid warn value (not a number)
assert_exit 2 "$SCRIPT --cpu-warn abc" "invalid warn value (non-numeric) exits 2"

# Invalid warn value (out of range)
assert_exit 2 "$SCRIPT --cpu-warn 101" "invalid warn value (>100) exits 2"
assert_exit 2 "$SCRIPT --cpu-warn -1" "invalid warn value (<0) exits 2"

# Invalid crit value
assert_exit 2 "$SCRIPT --cpu-crit abc" "invalid crit value (non-numeric) exits 2"
assert_exit 2 "$SCRIPT --cpu-crit 101" "invalid crit value (>100) exits 2"

# warn >= crit is invalid
assert_exit 2 "$SCRIPT --cpu-warn 90 --cpu-crit 90" "warn >= crit exits 2"
assert_exit 2 "$SCRIPT --cpu-warn 95 --cpu-crit 90" "warn > crit exits 2"

echo ""
echo "=== Testing remote host validation ==="

# Test valid host
assert_exit 0 "$SCRIPT --host 192.168.1.10" "valid IP exits 0"
assert_exit 0 "$SCRIPT --host user@server.com" "valid user@host exits 0"
assert_exit 0 "$SCRIPT --host localhost" "localhost exits 0"

# Test invalid host (starts with -)
assert_exit 2 "$SCRIPT --host -oProxyCommand=id" "option injection blocked, exits 2"

# Test invalid host (empty)
assert_exit 2 "$SCRIPT --host ''" "empty host exits 2"

# Test invalid host (bad characters)
assert_exit 2 "$SCRIPT --host 'server; whoami'" "semicolon blocked, exits 2"

# Test unreachable host (stub ssh exits 255)
assert_exit 2 "$SCRIPT --host 10.255.255.1" "unreachable host exits 2"

# Test forwarding thresholds to remote
output=$($SCRIPT --host localhost --cpu-warn 50 --cpu-crit 80 2>&1 | head -1)
assert "Host: localhost" "$output" "remote mode prints host header"

echo ""
echo "=== Test Summary ==="
echo "Passed: $tests_passed / $tests_run"

if [[ $tests_passed -eq $tests_run ]]; then
  exit 0
else
  exit 1
fi
