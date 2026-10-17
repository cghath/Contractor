#!/usr/bin/env bash
# CI must run exactly the default local suites, including new additions.
set -euo pipefail
cd "$(dirname "$0")/.."
local_suites="$(sed -n 's/^.*&& SUITES=(\(.*\))$/\1/p' tools/run_tests.sh | tr ' ' '\n' | sort)"
ci_suites="$(sed -n 's/^ *suite: \[\(.*\)\]$/\1/p' .github/workflows/tests.yml | tr -d ' ' | tr ',' '\n' | sort)"
if [ -z "$local_suites" ] || [ "$local_suites" != "$ci_suites" ]; then
	echo 'FAIL: CI and the default local suites differ' >&2
	diff -u <(printf '%s\n' "$local_suites") <(printf '%s\n' "$ci_suites") || true
	exit 1
fi
echo 'PASS: CI covers every default local suite'
