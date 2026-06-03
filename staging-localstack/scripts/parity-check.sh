#!/usr/bin/env bash
# Compare resource type counts between staging-multi-state (25 combined states)
# and staging-localstack (single state).
# Exits 0 if counts match, 1 if there are differences.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MULTI_STATE_DIR="$(cd "$SCRIPT_DIR/../../staging-multi-state" && pwd)"
SINGLE_STATE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }

# Aggregate resource type counts from all staging-multi-state tfstate files
multi_counts() {
  find "$MULTI_STATE_DIR" -maxdepth 2 -name "terraform.tfstate" | sort | while read -r f; do
    jq -r '
      .resources[]?
      | select(.mode == "managed")
      | .type
    ' "$f" 2>/dev/null || true
  done | sort | uniq -c | sort -rn
}

# Resource type counts from staging-localstack tfstate
single_counts() {
  local state="$SINGLE_STATE_DIR/terraform.tfstate"
  if [[ ! -f "$state" ]]; then
    echo "ERROR: $state not found. Run apply-and-export.sh first." >&2
    exit 1
  fi
  jq -r '
    .resources[]?
    | select(.mode == "managed")
    | .type
  ' "$state" 2>/dev/null | sort | uniq -c | sort -rn
}

echo "=== staging-multi-state resource type counts (combined 25 states) ==="
MULTI=$(multi_counts)
echo "$MULTI"
echo ""
echo "=== staging-localstack resource type counts (single state) ==="
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
