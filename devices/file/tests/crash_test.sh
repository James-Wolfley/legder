#!/usr/bin/env bash
# Kill the writer at random moments and check recovery.
#
#   ./crash_test.sh [ROUNDS] [DIR]
#
# Each round: fresh file, start "file_device_tests write", SIGKILL it
# after a random delay, then "file_device_tests check" with the last
# "ack N" the writer printed. Passes when every round recovers the
# acked prefix (or that plus the one Put in flight) and nothing else.
#
# SIGKILL stops the process at any instruction, including mid-write,
# but the kernel keeps its page cache, so this does not lose unsynced
# writes the way power loss does. For that, pull the plug on a board.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
bin="$here/bin/file_device_tests"
rounds="${1:-25}"
dir="${2:-$here/crash-tmp}"
mkdir -p "$dir"
fail=0
for r in $(seq 1 "$rounds"); do
  path="$dir/crash.ldgr"
  rm -f "$path" "$dir/out"
  "$bin" write "$path" > "$dir/out" &
  pid=$!
  # 0 .. 0.4 s, so some kills land during file creation and header write.
  sleep "0.$(printf '%03d' $((RANDOM % 400)))"
  kill -9 "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
  acked=$(grep -o '^ack [0-9]*' "$dir/out" | tail -1 | cut -d' ' -f2)
  printf 'round %2d: ' "$r"
  "$bin" check "$path" "${acked:-0}" || fail=1
done
rm -rf "$dir"
if [ "$fail" -ne 0 ]; then echo "CRASH TEST FAILED"; exit 1; fi
echo "crash test ok"
