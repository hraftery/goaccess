#!/bin/sh

# Die if a command exits with non-zero status. Makes writing tests easy because
# there's often no need to check the result. If it succeeds it succeeds.
set -eu

LOG_DIR=/var/log/nginx
LOGFILE=${LOG_DIR}/access.log
LOGFILE_OLD=${LOG_DIR}/access.log.1
DB_DIR=$(mktemp -d)
REPORT=$(mktemp --suffix=.html)
TOTAL=0
LINE_NUM=0

pass() { printf '  PASS: %s\n' "$*"; }
fail() { printf '  FAIL: %s\n' "$*" >&2; exit 1; }

# Each log entry gets a unique timestamp derived from LINE_NUM so goaccess's
# "skip lines with timestamp <= last seen" logic doesn't suppress new entries.
log_entry()
{
    LINE_NUM=$((LINE_NUM + 1))
    h=$(( LINE_NUM / 3600 ))
    m=$(( (LINE_NUM % 3600) / 60 ))
    s=$(( LINE_NUM % 60 ))
    printf '127.0.0.1 - - [01/Jan/2025:%02d:%02d:%02d +0000] "GET /request-%d HTTP/1.1" 200 512 "-" "TestAgent/1.0"\n' \
        "$h" "$m" "$s" "$LINE_NUM"
}

write_lines()
{
    n="${1:-3}"
    i=0
    while [ "$i" -lt "$n" ]; do
        log_entry >> "$LOGFILE"
        i=$((i + 1))
        TOTAL=$((TOTAL + 1))
    done
    printf '  Appended %d lines (cumulative total expected: %d)\n' "$n" "$TOTAL"
}

run_goaccess()
{
    # goaccess fails if a specified input file cannot be found, and the rotated log file
    # does not exist until the first rotation. So make sure it's there before specifying it.
    files="$LOGFILE"
    [ -f "$LOGFILE_OLD" ] && files="$files $LOGFILE_OLD"
    
    goaccess $files \
        --log-format=COMBINED \
        --restore \
        --persist \
        --db-path="$DB_DIR" \
        -o "$REPORT"
}

check_num_requests()
{
    # Pull the JSON data out of HTML file, and use jq to get the total_requests field.
    actual=$(tr -d '\n' < "$REPORT" | \
             sed 's/.*var json_data=//;s/<\/script>.*//' | \
             jq '.general.total_requests')
    if [ "$actual" -eq "$TOTAL" ]; then
        pass "total_requests = $actual"
    else
        fail "expected total_requests = $TOTAL, got $actual"
    fi
}

do_logrotate()
{
    "$(dirname "$0")/logrotate_one.sh" --force nginx
    printf '  Rotated nginx access.log.\n'
}

# ── Setup ────────────────────────────────────────────────────────────────────

# Nothing required

# ── Test 1: preparation ──────────────────────────────────────────────────────

printf '\n--- Test 1: make sure goaccess works ---\n'
goaccess --version

# ── Test 2: initial write and parse ─────────────────────────────────────────

printf '\n--- Test 2: first write + parse ---\n'
write_lines 3
run_goaccess
check_num_requests

# ── Test 3: DB grows with more lines ─────────────────────────────────────────

printf '\n--- Test 3: second write + parse (DB should grow) ---\n'
write_lines 3
run_goaccess
check_num_requests

# ── Test 4: first logrotate ───────────────────────────────────────────────────

printf '\n--- Test 4: write + first logrotate + write + parse ---\n'
write_lines 3
do_logrotate
write_lines 3
run_goaccess
check_num_requests

# ── Test 5: DB grows after first logrotate ───────────────────────────────────

printf '\n--- Test 5: no write + parse (DB should not grow) ---\n'
run_goaccess
check_num_requests

# ── Test 6: second logrotate ──────────────────────────────────────────────────

printf '\n--- Test 6: second logrotate + no write + parse ---\n'
do_logrotate
run_goaccess
check_num_requests

# ── Test 7: DB grows after second logrotate ───────────────────────────────────

printf '\n--- Test 7: write + parse after second logrotate (DB should grow) ---\n'
write_lines 3
run_goaccess
check_num_requests

printf '\n--- All tests passed! ---\n'
