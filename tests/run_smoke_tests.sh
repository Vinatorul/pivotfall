#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd -- "$script_dir/.." && pwd)"
godot_bin="${GODOT_BIN:-godot}"
log_dir="${SMOKE_LOG_DIR:-$project_root/builds/logs/smoke}"
timeout_seconds="${SMOKE_TEST_TIMEOUT_SECONDS:-300}"

if [[ ! "$timeout_seconds" =~ ^[0-9]+$ ]]; then
	printf 'Invalid SMOKE_TEST_TIMEOUT_SECONDS: %s\n' "$timeout_seconds" >&2
	exit 2
fi

if (( $# > 0 )); then
	test_files=("$@")
else
	test_files=("$project_root"/tests/*_smoke.gd)
fi

timeout_bin=""
if (( timeout_seconds > 0 )); then
	if command -v timeout >/dev/null 2>&1; then
		timeout_bin="$(command -v timeout)"
	elif command -v gtimeout >/dev/null 2>&1; then
		timeout_bin="$(command -v gtimeout)"
	else
		printf '%s\n' \
			'warning: timeout utility unavailable; per-test timeout disabled' >&2
	fi
fi

mkdir -p "$log_dir"
passed=0

for candidate in "${test_files[@]}"; do
	if [[ "$candidate" != /* ]]; then
		candidate="$project_root/$candidate"
	fi

	if [[ ! -f "$candidate" ]]; then
		printf 'Smoke test not found: %s\n' "$candidate" >&2
		exit 2
	fi

	case "$candidate" in
		"$project_root"/tests/*_smoke.gd) ;;
		*)
			printf 'Unexpected smoke-test path: %s\n' "$candidate" >&2
			exit 2
			;;
	esac

	test_name="${candidate##*/}"
	marker="$(
		printf '%s_OK' "${test_name%.gd}" |
			tr '[:lower:]' '[:upper:]'
	)"
	log_file="$log_dir/${test_name%.gd}.log"
	: >"$log_file"

	printf '=== RUN %s ===\n' "$test_name"
	if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
		printf '::group::%s\n' "$test_name"
	fi

	command=(
		"$godot_bin"
		--headless
		--fixed-fps 60
		--path "$project_root"
		--log-file "$log_file"
		--script "res://tests/$test_name"
	)
	if [[ -n "$timeout_bin" ]]; then
		command=(
			"$timeout_bin"
			--signal=TERM
			--kill-after=10s
			"${timeout_seconds}s"
			"${command[@]}"
		)
	fi

	if "${command[@]}"; then
		status=0
	else
		status=$?
	fi

	if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
		printf '%s\n' '::endgroup::'
	fi

	reason=""
	if (( status != 0 )); then
		reason="Godot exited with status $status"
	elif grep -Eq 'SCRIPT ERROR:|Failed to load script' "$log_file"; then
		reason="log contains a script/load error"
	elif ! grep -Fxq "$marker" "$log_file"; then
		reason="missing success marker $marker"
	fi

	if [[ -n "$reason" ]]; then
		printf '\nRUNNER FAILURE: %s: %s\n' "$test_name" "$reason" >>"$log_file"
		printf 'FAILED: %s: %s\n' "$test_name" "$reason" >&2
		if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
			printf \
				'::error file=tests/%s,title=Godot smoke failed::%s: %s\n' \
				"$test_name" "$test_name" "$reason"
		fi
		exit 1
	fi

	passed=$((passed + 1))
	printf 'PASS: %s\n' "$test_name"
done

printf 'All %d smoke tests passed.\n' "$passed"
