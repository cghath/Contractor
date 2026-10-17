#!/usr/bin/env bash
# Audit-only scene substitution. Gameplay sources are untouched.
args=()
for arg in "$@"; do
  case "$arg" in
    res://tests/executive_audit_test.tscn) arg=res://docs/audits/executive-2026-10-17/probe.tscn ;;
  esac
  args+=("$arg")
done
exec "$AUDIT_REAL_GODOT" "${args[@]}"
