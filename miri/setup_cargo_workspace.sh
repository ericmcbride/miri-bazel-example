#!/bin/sh
set -e

CARGO_TOML="$1"
WORKSPACE_ROOT="$2"
OUT_DIR="$3"

# Extract workspace members
MEMBERS=$(awk '/members/,/]/' "$CARGO_TOML" | grep -o '"[^"]*"' | tr -d '"' | grep -v '^members$' | grep '/')

echo "Found workspace members: $MEMBERS"

for member in $MEMBERS; do
  echo "Setting up member: $member"
  mkdir -p "$OUT_DIR/$member"

  if [ -f "$WORKSPACE_ROOT/$member/Cargo.toml" ]; then
    ln -sf "$WORKSPACE_ROOT/$member/Cargo.toml" "$OUT_DIR/$member/Cargo.toml"
  fi

  if [ -d "$WORKSPACE_ROOT/$member" ]; then
    find "$WORKSPACE_ROOT/$member" -name "*.rs" -not -path "*/bazel-*/*" -not -path "*/target/*" | while IFS= read -r rs_file; do
      rel="${rs_file#$WORKSPACE_ROOT/$member/}"
      mkdir -p "$OUT_DIR/$member/$(dirname "$rel")"
      ln -sf "$rs_file" "$OUT_DIR/$member/$rel"
    done
  fi
done

cat >"$OUT_DIR/BUILD.bazel" <<'EOF'
package(default_visibility = ["//visibility:public"])
filegroup(
    name = "cargo_files",
    srcs = glob([
        "Cargo.toml",
        "Cargo.lock",
        "**/Cargo.toml",
        "**/*.rs",
    ], allow_empty = True),
)
EOF
