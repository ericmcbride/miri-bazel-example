"""Builds the Miri sysroot via cargo miri setup."""

def _nightly_transition_impl(settings, attr):
    return {
        "@rules_rust//rust/toolchain/channel:channel": "nightly",
    }

_nightly_transition = transition(
    implementation = _nightly_transition_impl,
    inputs = [],
    outputs = [
        "@rules_rust//rust/toolchain/channel:channel",
    ],
)

MiriSysrootInfo = provider(
    doc = "Information about the built Miri sysroot.",
    fields = {
        "sysroot_dir": "Directory containing the Miri sysroot",
    },
)

def _miri_sysroot_impl(ctx):
    cargo_miri = ctx.executable.cargo_miri_bin
    miri_bin = ctx.executable.miri_bin
    rust_src_files = ctx.files.rust_src

    rust_toolchain = ctx.toolchains["@rules_rust//rust:toolchain_type"]
    rustc = rust_toolchain.rustc
    cargo = rust_toolchain.cargo
    rustc_lib_files = rust_toolchain.rustc_lib.to_list()
    all_toolchain_files = rust_toolchain.all_files.to_list()

    if not rustc_lib_files:
        fail("rustc_lib is empty")

    anchor_lib = rustc_lib_files[0]

    sysroot_dir = ctx.actions.declare_directory(ctx.label.name)

    setup_script = ctx.actions.declare_file(ctx.label.name + "_setup.sh")

    ctx.actions.write(
        output = setup_script,
        content = """\
#!/usr/bin/env bash
set -euo pipefail

ANCHOR_LIB="$(cd "$(dirname "{anchor_lib}")" && pwd -P)/$(basename "{anchor_lib}")"
LIB_DIR="$(dirname "$ANCHOR_LIB")"

export DYLD_LIBRARY_PATH="${{LIB_DIR}}:${{DYLD_LIBRARY_PATH:-}}"
export LD_LIBRARY_PATH="${{LIB_DIR}}:${{LD_LIBRARY_PATH:-}}"

RUSTC_ABS="$(cd "$(dirname "{rustc}")" && pwd -P)/$(basename "{rustc}")"
CARGO_ABS="$(cd "$(dirname "{cargo}")" && pwd -P)/$(basename "{cargo}")"
MIRI_ABS="$(cd "$(dirname "{miri_bin}")" && pwd -P)/$(basename "{miri_bin}")"
CARGO_MIRI_ABS="$(cd "$(dirname "{cargo_miri}")" && pwd -P)/$(basename "{cargo_miri}")"

RUSTC_SYSROOT="$($RUSTC_ABS --print sysroot)"

RUST_SRC_LIB="$(find "$(pwd)" -type d -name "library" -path "*/rust-src/*" 2>/dev/null | head -1)"

if [[ -z "$RUST_SRC_LIB" ]]; then
    echo "ERROR: Could not find rust-src library directory"
    exit 1
fi

RUSTLIB_SRC_DIR="$RUSTC_SYSROOT/lib/rustlib/src/rust"
mkdir -p "$RUSTLIB_SRC_DIR"
ln -sf "$RUST_SRC_LIB" "$RUSTLIB_SRC_DIR/library"

if [[ -f "$RUST_SRC_LIB/Cargo.lock" ]]; then
    ln -sf "$RUST_SRC_LIB/Cargo.lock" "$RUSTLIB_SRC_DIR/Cargo.lock"
fi
if [[ -f "$RUST_SRC_LIB/Cargo.toml" ]]; then
    ln -sf "$RUST_SRC_LIB/Cargo.toml" "$RUSTLIB_SRC_DIR/Cargo.toml"
fi

OUTPUT_DIR="$(cd "$(dirname "{output}")" && pwd -P)/$(basename "{output}")"
export MIRI_SYSROOT="$OUTPUT_DIR"

CARGO_TEMP="$(mktemp -d)"
export CARGO_HOME="$CARGO_TEMP"

FAKE_BIN="$(mktemp -d)"
cat > "$FAKE_BIN/rustup" << 'RUSTUP_SHIM'
#!/usr/bin/env bash
echo "info: component 'rust-src' is up to date"
exit 0
RUSTUP_SHIM
chmod +x "$FAKE_BIN/rustup"

ln -sf "$RUSTC_ABS" "$FAKE_BIN/rustc"
ln -sf "$CARGO_ABS" "$FAKE_BIN/cargo"
ln -sf "$MIRI_ABS" "$FAKE_BIN/miri"
ln -sf "$CARGO_MIRI_ABS" "$FAKE_BIN/cargo-miri"
export PATH="${{FAKE_BIN}}:$PATH"

unset RUSTUP_TOOLCHAIN
unset RUSTUP_HOME

echo "Building Miri sysroot..."
echo "  rustc:          $RUSTC_ABS"
echo "  rustc ver:      $(rustc --version)"
echo "  rustc sysroot:  $RUSTC_SYSROOT"
echo "  cargo home:     $CARGO_HOME"
echo "  rust-src:       $RUST_SRC_LIB"
echo "  output:         $OUTPUT_DIR"

"$CARGO_MIRI_ABS" miri setup 2>&1

RLIB_COUNT=$(find "$OUTPUT_DIR" -name "*.rlib" 2>/dev/null | wc -l | tr -d ' ')
RMETA_COUNT=$(find "$OUTPUT_DIR" -name "*.rmeta" 2>/dev/null | wc -l | tr -d ' ')
echo "rlib files: $RLIB_COUNT"
echo "rmeta files: $RMETA_COUNT"

rm -rf "$FAKE_BIN" "$CARGO_TEMP"

echo "Miri sysroot built at: $OUTPUT_DIR"
""".format(
            anchor_lib = anchor_lib.path,
            rustc = rustc.path,
            cargo = cargo.path,
            miri_bin = miri_bin.path,
            cargo_miri = cargo_miri.path,
            output = sysroot_dir.path,
        ),
        is_executable = True,
    )

    ctx.actions.run(
        outputs = [sysroot_dir],
        inputs = (
            [cargo_miri, miri_bin, rustc, cargo] +
            rust_src_files +
            rustc_lib_files +
            all_toolchain_files
        ),
        executable = setup_script,
        tools = [setup_script],
        mnemonic = "MiriSysroot",
        progress_message = "Building Miri sysroot",
        use_default_shell_env = True,
    )

    return [
        DefaultInfo(files = depset([sysroot_dir])),
        MiriSysrootInfo(sysroot_dir = sysroot_dir),
    ]

miri_sysroot = rule(
    implementation = _miri_sysroot_impl,
    cfg = _nightly_transition,
    attrs = {
        "cargo_miri_bin": attr.label(
            mandatory = True,
            allow_single_file = True,
            executable = True,
            cfg = "exec",
        ),
        "miri_bin": attr.label(
            mandatory = True,
            allow_single_file = True,
            executable = True,
            cfg = "exec",
        ),
        "rust_src": attr.label(
            mandatory = True,
            allow_files = True,
        ),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    },
    toolchains = ["@rules_rust//rust:toolchain_type"],
    doc = "Builds the Miri sysroot with -Zalways-encode-mir.",
)
