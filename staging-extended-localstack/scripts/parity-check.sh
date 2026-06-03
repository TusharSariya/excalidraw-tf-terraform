#!/usr/bin/env bash
# Compare managed resource type counts between staging-multi-state (25 combined
# plans) and staging-extended-localstack (single plan).
# Exits 0 if counts match, 1 if there are differences.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MULTI_STATE_DIR="$(cd "$SCRIPT_DIR/../../staging-multi-state" && pwd)"
SINGLE_STATE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }

# Aggregate resource type counts from all staging-multi-state plan files
multi_counts() {
  find "$MULTI_STATE_DIR" -maxdepth 2 -name "plan.json" | sort | while read -r f; do
    jq -r '
      .resource_changes[]?
      | select(.mode == "managed")
      | .type
    ' "$f" 2>/dev/null || true
  done | sort | uniq -c | sort -rn
}

# Resource type counts from staging-extended-localstack plan
single_counts() {
  local plan="$SINGLE_STATE_DIR/plan.json"
  if [[ ! -f "$plan" ]]; then
    echo "ERROR: $plan not found. Run apply-and-export.sh first." >&2
    exit 1
  fi
  jq -r '
    .resource_changes[]?
    | select(.mode == "managed")
    | .type
  ' "$plan" 2>/dev/null | sort | uniq -c | sort -rn
}

echo "=== staging-multi-state resource type counts (combined 25 plans) ==="
MULTI=$(multi_counts)
echo "$MULTI"
echo ""
echo "=== staging-extended-localstack resource type counts (single plan) ==="
SINGLE=$(single_counts)
echo "$SINGLE"
echo ""

# Diff the two count tables
MULTI_NORMALIZED=$(echo "$MULTI" | awk '{print $2, $1}' | sort)
SINGLE_NORMALIZED=$(echo "$SINGLE" | awk '{print $2, $1}' | sort)

DIFF=$(diff <(echo "$MULTI_NORMALIZED") <(echo "$SINGLE_NORMALIZED") || true)

if [[ -z "$DIFF" ]]; then
  echo "✓ PARITY OK — resource type counts match exactly."
  exit 0
else
  echo "✗ PARITY MISMATCH — differences (< multi-state  > localstack):"
  echo "$DIFF"
  echo ""
  echo "Run apply-and-export.sh, fix discrepancies, repeat until clean."
  exit 1
fi
