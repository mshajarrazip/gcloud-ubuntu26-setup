#!/usr/bin/env bash
#
# process-trace.sh - Sample CPU / memory / load and the top processes once a
# minute, appending each snapshot to /tmp/process-trace-<timestamp>.log.
#
# Roughly the htop "summary" area plus its process list, captured over time so
# you can go back and see what a box was doing when it got busy.
#
# Each sample records:
#   - wall-clock time and uptime / load average
#   - per-CPU and total utilisation (from top)
#   - task counts (from top)
#   - memory + swap usage (free -h)
#   - the top processes by CPU, then by memory (ps)
#
# Usage:
#   ./process-trace.sh                 # sample every 60s until Ctrl-C
#   ./process-trace.sh -i 30           # sample every 30s
#   ./process-trace.sh -n 60           # take 60 samples, then stop
#   ./process-trace.sh -i 10 -n 360    # every 10s for an hour
#
# The log path is printed on startup. Runs in the foreground; background it
# with `nohup ./process-trace.sh &` or a tmux/systemd unit if you want.

set -euo pipefail

INTERVAL=60          # seconds between samples
SAMPLES=0            # 0 = run forever
TOP_N=15             # processes to list per sort key

usage() {
  sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while getopts ':i:n:t:h' opt; do
  case "${opt}" in
    i) INTERVAL="${OPTARG}" ;;
    n) SAMPLES="${OPTARG}" ;;
    t) TOP_N="${OPTARG}" ;;
    h) usage 0 ;;
    \?) echo "Unknown option: -${OPTARG}" >&2; usage 1 ;;
    :)  echo "Option -${OPTARG} needs a value" >&2; usage 1 ;;
  esac
done

for v in INTERVAL SAMPLES TOP_N; do
  case "${!v}" in
    ''|*[!0-9]*) echo "${v} must be a non-negative integer" >&2; exit 1 ;;
  esac
done
[ "${INTERVAL}" -ge 1 ] || { echo "INTERVAL must be >= 1" >&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

LOG="/tmp/process-trace-$(date +%Y%m%dT%H%M%S).log"

emit() { printf '%s\n' "$*" >>"${LOG}"; }

sample() {
  local now
  now="$(date '+%Y-%m-%d %H:%M:%S %z')"

  emit "================================================================================"
  emit "sample ${1}    ${now}"
  emit "--------------------------------------------------------------------------------"

  emit "# uptime / load"
  emit "$(uptime)"
  emit ""

  emit "# cpu + tasks (top)"
  # -b batch, -1 expand per-CPU lines, -w512 wide output. Two iterations 0.5s
  # apart so the %Cpu figures are a real interval, not since-boot averages;
  # keep only the last summary block and drop top's own PID list (we render
  # our own below from ps).
  top -b -n2 -d 0.5 -1 -w 512 2>/dev/null \
    | awk '/^top - /{buf=""} {buf=buf $0 "\n"} END{printf "%s", buf}' \
    | sed -n '1,/^[[:space:]]*PID[[:space:]]\+USER/p' \
    | sed '/^[[:space:]]*PID[[:space:]]\+USER/d' \
    | sed '/^[[:space:]]*$/d' >>"${LOG}" || emit "(top unavailable)"
  emit ""

  if have mpstat; then
    emit "# per-core (mpstat 1s)"
    mpstat -P ALL 1 1 2>/dev/null | sed '/^$/d' >>"${LOG}" || emit "(mpstat failed)"
    emit ""
  fi

  emit "# memory (free -h)"
  free -h >>"${LOG}" 2>/dev/null || emit "(free unavailable)"
  emit ""

  emit "# top ${TOP_N} by %CPU"
  ps -eo pid,ppid,user,pcpu,pmem,rss,stat,etime,args --sort=-pcpu \
    | head -n "$((TOP_N + 1))" >>"${LOG}"
  emit ""

  emit "# top ${TOP_N} by %MEM"
  ps -eo pid,ppid,user,pcpu,pmem,rss,stat,etime,args --sort=-pmem \
    | head -n "$((TOP_N + 1))" >>"${LOG}"
  emit ""
}

main() {
  : >"${LOG}"
  emit "# process-trace started $(date '+%Y-%m-%d %H:%M:%S %z') on $(hostname)"
  emit "# interval=${INTERVAL}s samples=$([ "${SAMPLES}" -eq 0 ] && echo infinite || echo "${SAMPLES}") pid=$$"
  emit "# kernel=$(uname -r) cpus=$(nproc 2>/dev/null || echo '?')"
  emit ""

  echo "Writing to ${LOG} (every ${INTERVAL}s). Ctrl-C to stop."

  trap 'emit ""; emit "# process-trace stopped $(date "+%Y-%m-%d %H:%M:%S %z")"; exit 0' INT TERM

  local i=1
  while :; do
    sample "${i}"
    if [ "${SAMPLES}" -ne 0 ] && [ "${i}" -ge "${SAMPLES}" ]; then
      emit "# process-trace finished ${SAMPLES} samples $(date '+%Y-%m-%d %H:%M:%S %z')"
      break
    fi
    i="$((i + 1))"
    sleep "${INTERVAL}"
  done
}

main "$@"
