#!/usr/bin/env bash
# Verify resolve-upstream.sh derives the version from a stable tag and rejects any
# tag pair whose shape it does not recognise.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
resolve="$here/../resolve-upstream.sh"

fail=0

expect_ok() {  # expect_ok <label> <stable> <nightly> <expected-output>
    local label=$1 out status=0
    out=$("$resolve" "$2" "$3" 2>/dev/null) || status=$?
    if [ "$status" != 0 ]; then
        printf 'FAIL  %s (expected exit 0, got %s)\n' "$label" "$status"
        fail=1
    elif [ "$out" != "$4" ]; then
        printf 'FAIL  %s\n       expected: %s\n       got:      %s\n' "$label" \
            "$(printf '%s' "$4" | tr '\n' ' ')" "$(printf '%s' "$out" | tr '\n' ' ')"
        fail=1
    else
        printf 'ok    %s\n' "$label"
    fi
}

expect_reject() {  # expect_reject <label> <arg>...
    local label=$1 status=0
    shift
    "$resolve" "$@" >/dev/null 2>&1 || status=$?
    if [ "$status" = 2 ]; then
        printf 'ok    %s\n' "$label"
    else
        printf 'FAIL  %s (expected exit 2, got %s)\n' "$label" "$status"
        fail=1
    fi
}

# The pair upstream published when it split stable from nightly.
expect_ok "a matched pair resolves" v0.2.0 b10566 \
'tag=v0.2.0
nightly=b10566
version=0.2.0'

# A two-digit component must survive intact, since 0.10.0 outranks 0.2.0.
expect_ok "a two-digit minor resolves" v0.10.3 b11000 \
'tag=v0.10.3
nightly=b11000
version=0.10.3'

# The failure of 2026-08-23: releases/latest returned the stable tag, which was
# then used as though it named the nightly archives, and the download 404ed.
expect_reject "a stable tag in the nightly position is rejected" v0.2.0 v0.2.0

# The mirror image, which used to yield the nonsense version 0.0.v0.2.0.
expect_reject "a nightly tag in the stable position is rejected" b10566 b10566

# An absent or empty nightly-tag.txt must not resolve to an empty archive name.
expect_reject "an empty nightly is rejected" v0.2.0 ""
expect_reject "an empty stable is rejected" "" b10566

# A prerelease never reaches releases/latest, so treat it as unrecognised.
expect_reject "a release candidate is rejected" v0.3.0-rc1 b10600

expect_reject "a truncated stable tag is rejected" v0.2 b10566
expect_reject "a non-numeric nightly is rejected" v0.2.0 bnightly
expect_reject "a nightly with trailing whitespace is rejected" v0.2.0 "b10566 "
expect_reject "a missing argument is rejected" v0.2.0

exit "$fail"
