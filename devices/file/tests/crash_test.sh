#!/usr/bin/env bash
# Kill the writer at random moments and check recovery.
#
#   ./crash_test.sh [ROUNDS] [PARENT]
#
# Each round: fresh file in a child of PARENT, start "file_device_tests
# write", SIGKILL it after a random delay, then "file_device_tests
# check" with the last "ack N" the writer printed. Passes when the
# process was really killed and every round recovers the acked prefix
# (or that plus the one Put in flight) and nothing else. A writer that
# finishes normally, fails to open, or dies before creating the file is
# not a crash round; the round retries with a better delay or fails.
#
# The test creates and removes its own child of PARENT and never
# deletes PARENT itself.
#
# SIGKILL stops the process at any instruction, including mid-write,
# but the kernel keeps its page cache, so this does not lose unsynced
# writes the way power loss does. For that, pull the plug on a board.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
bin="$here/bin/file_device_tests"
rounds="${1:-25}"
parent="${2:-$here}"
mkdir -p "$parent" || exit 1
dir="$(mktemp -d "$parent/crash-test.XXXXXX")" || {
  echo "cannot create a test directory under $parent"
  exit 1
}
trap 'rm -rf "$dir"' EXIT
fail=0
for r in $(seq 1 "$rounds"); do
  attempt=0
  max=400
  while :; do
    attempt=$((attempt + 1))
    path="$dir/crash.ldgr"
    out="$dir/out"
    rm -f "$path" "$out"
    "$bin" write "$path" > "$out" &
    pid=$!
    # 0 .. max ms, so some kills land during file creation and header write.
    sleep "0.$(printf '%03d' $((RANDOM % max)))"
    kill -9 "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    status=$?
    if grep -q '^full$' "$out"; then
      #  The writer finished before the signal landed: not a crash.
      if [ "$attempt" -ge 40 ]; then
        printf 'round %2d: FAIL  writer always finished before the kill\n' "$r"
        fail=1
        break
      fi
      if [ "$max" -gt 1 ]; then max=$((max / 2)); fi
      continue
    fi
    if [ "$status" -ne 137 ]; then
      printf 'round %2d: FAIL  writer exited %d, not killed\n' "$r" "$status"
      fail=1
      break
    fi
    if [ ! -e "$path" ]; then
      #  Killed before it created the image; aim later and retry.
      if [ "$attempt" -ge 40 ]; then
        printf 'round %2d: FAIL  writer always died before creating the file\n' "$r"
        fail=1
        break
      fi
      max=$((max + max / 2 + 1))
      if [ "$max" -gt 400 ]; then max=400; fi
      continue
    fi
    printf 'round %2d: ' "$r"
    acked=$(grep -o '^ack [0-9]*' "$out" | tail -1 | cut -d' ' -f2)
    "$bin" check "$path" "${acked:-0}" || fail=1
    break
  done
done
if [ "$fail" -ne 0 ]; then echo "CRASH TEST FAILED"; exit 1; fi
echo "crash test ok"
