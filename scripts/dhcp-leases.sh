#!/usr/bin/env bash
# Live (or one-shot) view of DHCP4 leases via the Kea control channel.
#
# Usage:
#   scripts/dhcp-leases.sh [options] [URL]
#
# Options:
#   -k, --insecure   Skip TLS certificate verification (curl -k)
#   -n, --once       Print once and exit (also default when stdout is not a TTY)
#   -i, --interval N Refresh every N seconds (default: 5; interactive only)
#   -h, --help       Show help
#
# URL defaults to KEA_CONTROL_URL or http://127.0.0.1:8001/
# Optional mTLS: KEA_CA, KEA_CERT, KEA_KEY (PEM paths for curl).
# Colors follow NO_COLOR / TERM=dumb / non-TTY stdout.
set -euo pipefail

URL="${KEA_CONTROL_URL:-http://127.0.0.1:8001/}"
INTERVAL="${KEA_LEASES_INTERVAL:-5}"
INSECURE="${KEA_INSECURE:-0}"
ONCE=0

usage() {
  cat <<'EOF'
Live (or one-shot) view of DHCP4 leases via the Kea control channel.

Usage:
  scripts/dhcp-leases.sh [options] [URL]

Options:
  -k, --insecure   Skip TLS certificate verification (curl -k)
  -n, --once       Print once and exit (also default when stdout is not a TTY)
  -i, --interval N Refresh every N seconds (default: 5; interactive only)
  -h, --help       Show help

URL defaults to KEA_CONTROL_URL or http://127.0.0.1:8001/
Optional mTLS: KEA_CA, KEA_CERT, KEA_KEY (PEM paths for curl).
Colors follow NO_COLOR / TERM=dumb / non-TTY stdout.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -k|--insecure) INSECURE=1; shift ;;
    -n|--once) ONCE=1; shift ;;
    -i|--interval)
      if [[ $# -lt 2 ]]; then
        echo "-i/--interval requires a positive integer" >&2
        exit 2
      fi
      INTERVAL="$2"
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    --) shift; break ;;
    -*)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      URL="$1"
      shift
      break
      ;;
  esac
done
# Allow: dhcp-leases.sh -i 2 http://host:8001/
[[ $# -gt 0 ]] && URL="$1"

if ! [[ "$INTERVAL" =~ ^[1-9][0-9]*$ ]]; then
  echo "interval must be a positive integer (seconds)" >&2
  exit 2
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required" >&2
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required" >&2
  exit 1
fi

# Normalize URL: ensure trailing slash for Kea HTTP API
[[ "$URL" == */ ]] || URL="${URL}/"

USE_COLOR=1
if [[ -n "${NO_COLOR:-}" ]] || [[ "${TERM:-}" == "dumb" ]] || [[ ! -t 1 ]]; then
  USE_COLOR=0
fi
if [[ ! -t 1 ]]; then
  ONCE=1
fi

CURL_OPTS=(
  -sS
  --connect-timeout 3
  --max-time 15
  -X POST
  -H "Content-Type: application/json"
  -d '{"command":"lease4-get-all","service":["dhcp4"]}'
)
[[ "$INSECURE" == "1" ]] && CURL_OPTS+=(-k)
[[ -n "${KEA_CA:-}" ]] && CURL_OPTS+=(--cacert "$KEA_CA")
[[ -n "${KEA_CERT:-}" ]] && CURL_OPTS+=(--cert "$KEA_CERT")
[[ -n "${KEA_KEY:-}" ]] && CURL_OPTS+=(--key "$KEA_KEY")

fetch_leases() {
  local raw err
  err="$(mktemp)"
  if ! raw="$(curl "${CURL_OPTS[@]}" "$URL" 2>"$err")"; then
    printf 'ERROR: request failed for %s\n' "$URL" >&2
    if [[ -s "$err" ]]; then
      sed 's/^/  /' "$err" >&2
    fi
    rm -f "$err"
    return 1
  fi
  rm -f "$err"
  if [[ -z "$raw" ]]; then
    printf 'ERROR: empty response from %s\n' "$URL" >&2
    return 1
  fi
  printf '%s' "$raw"
}

format_leases() {
  KEA_RAW="$1" KEA_COLOR="$USE_COLOR" python3 - <<'PY'
import json, os, sys
from datetime import datetime

use_color = os.environ.get("KEA_COLOR", "1") == "1"

def c(*codes):
    if not use_color:
        return ""
    return "".join(f"\033[{n}m" for n in codes)

RST = c(0)
BOLD = c(1)
DIM = c(2)
GREEN = c(32)
RED = c(31)
YELLOW = c(33)
CYAN = c(36)

def trunc(s, width):
    s = s if s else "-"
    if len(s) <= width:
        return s
    if width <= 1:
        return s[:width]
    return s[: width - 1] + ">"

try:
    data = json.loads(os.environ["KEA_RAW"])
except json.JSONDecodeError as e:
    print(f"{RED}{BOLD}ERROR{RST} invalid JSON from control channel: {e}", file=sys.stderr)
    sys.exit(1)

if not isinstance(data, list) or not data:
    print(f"{RED}{BOLD}ERROR{RST} unexpected control response (expected Kea list)", file=sys.stderr)
    sys.exit(1)

result = data[0]
if result.get("result", 0) != 0:
    text = result.get("text", "unknown error")
    print(f"{RED}{BOLD}ERROR{RST} Kea: {text}", file=sys.stderr)
    sys.exit(1)

leases = result.get("arguments", {}).get("leases", []) or []
if not leases:
    print(f"  {DIM}No leases found.{RST}")
    sys.exit(0)

states = {0: "ACTIVE", 1: "DECLINED", 2: "EXPIRED", 3: "RELEASED"}
state_colors = {0: GREEN, 1: YELLOW, 2: RED, 3: DIM}
now = datetime.now().astimezone()

hdr = (
    f"  {BOLD}{'IP Address':<18} {'MAC Address':<18} {'Hostname':<28} "
    f"{'State':<10} {'Sub':<5} {'Expires':<19} {'TTL'}{RST}"
)
print(hdr)
print(f"  {DIM}{'-' * 110}{RST}")

for lease in sorted(leases, key=lambda x: (x.get("state", 0), x.get("ip-address", ""))):
    cltt = int(lease.get("cltt", 0))
    valid = int(lease.get("valid-lft", 0))
    exp_ts = cltt + valid
    exp = datetime.fromtimestamp(exp_ts).astimezone().strftime("%Y-%m-%d %H:%M:%S")
    state_id = int(lease.get("state", 0))
    state = states.get(state_id, str(state_id))
    color = state_colors.get(state_id, "")
    hostname = trunc(lease.get("hostname") or "-", 28)
    remaining = exp_ts - int(now.timestamp())
    if remaining > 0:
        h, rem = divmod(remaining, 3600)
        m = rem // 60
        ttl = f"{h}h {m:02d}m"
    else:
        ttl = f"{RED}expired{RST}"

    ip = trunc(lease.get("ip-address", "?"), 18)
    mac = trunc(lease.get("hw-address", "?"), 18)
    sid = str(lease.get("subnet-id", "-"))
    print(
        f"  {CYAN}{ip:<18}{RST} {DIM}{mac:<18}{RST} {hostname:<28} "
        f"{color}{BOLD}{state:<10}{RST} {sid:<5} {DIM}{exp:<19}{RST} {ttl}"
    )

active = sum(1 for l in leases if l.get("state") == 0)
declined = sum(1 for l in leases if l.get("state") == 1)
expired = sum(1 for l in leases if l.get("state") == 2)
print(f"  {DIM}{'-' * 110}{RST}")
parts = [f"{BOLD}{len(leases)}{RST} total"]
if active:
    parts.append(f"{GREEN}{BOLD}{active}{RST} active")
if declined:
    parts.append(f"{YELLOW}{BOLD}{declined}{RST} declined")
if expired:
    parts.append(f"{RED}{BOLD}{expired}{RST} expired")
print(f"  {' | '.join(parts)}")
PY
}

render_once() {
  local raw
  raw="$(fetch_leases)" || return 1
  format_leases "$raw"
}

if [[ "$ONCE" -eq 1 ]]; then
  render_once
  exit $?
fi

# Interactive: alternate screen + hide cursor; always restore on exit.
cleanup() {
  printf '\033[?25h\033[?1049l' 2>/dev/null || printf '\033[?25h'
}
trap cleanup EXIT INT TERM HUP

printf '\033[?1049h\033[?25l'

while true; do
  printf '\033[H\033[J'
  if [[ "$USE_COLOR" -eq 1 ]]; then
    printf '  \033[44m\033[1m\033[37m KEA DHCP4 LEASES \033[0m  \033[1m%s\033[0m  \033[2m%s\033[0m  \033[2m(every %ss, Ctrl-C to quit)\033[0m\n\n' \
      "$URL" "$(date '+%H:%M:%S')" "$INTERVAL"
  else
    printf '  KEA DHCP4 LEASES  %s  %s  (every %ss, Ctrl-C to quit)\n\n' \
      "$URL" "$(date '+%H:%M:%S')" "$INTERVAL"
  fi
  if ! render_once; then
    printf '\n  (retrying...)\n'
  fi
  printf '\n'
  sleep "$INTERVAL"
done
