"""Miri test rule — runs tests via cargo miri test."""

load("@rules_rust//rust:defs.bzl", "rust_common")
load("//miri:miri_sysroot.bzl", "MiriSysrootInfo")
load("//miri:transition.bzl", "miri_nightly_transition")

def _miri_test_impl(ctx):
    miri_bin = ctx.executable._miri_bin
    cargo_miri_bin = ctx.executable._cargo_miri_bin
    miri_all_files = ctx.files._miri_all_files
    cargo_workspace_files = ctx.files._cargo_workspace

    rust_toolchain = ctx.toolchains["@rules_rust//rust:toolchain_type"]
    rustc = rust_toolchain.rustc
    cargo = rust_toolchain.cargo
    rustc_lib_files = rust_toolchain.rustc_lib.to_list()

    if not rustc_lib_files:
        fail("rustc_lib is empty")

    anchor_lib = rustc_lib_files[0]

    sysroot_info = ctx.attr._miri_sysroot[MiriSysrootInfo]
    sysroot_dir = sysroot_info.sysroot_dir

    target = ctx.attr.target

    crate_info = None
    if rust_common.crate_info in target:
        crate_info = target[rust_common.crate_info]

    if crate_info:
        root_src = crate_info.root
        edition = crate_info.edition
        srcs = crate_info.srcs.to_list()
        crate_name = crate_info.name
    else:
        srcs = target[DefaultInfo].files.to_list()
        if not srcs:
            fail("No source files found on target {}".format(ctx.attr.target.label))
        root_src = srcs[0]
        edition = ctx.attr.edition
        crate_name = ctx.attr.crate_name if ctx.attr.crate_name else ctx.label.name

    miri_flags = ctx.attr.miri_flags

    env_lines = ""
    for k, v in ctx.attr.env.items():
        env_lines += "export {}='{}'\
".format(k, v)

    runner = ctx.actions.declare_file(ctx.label.name + "_miri.sh")

    script = """\
#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${{RUNFILES_DIR:-}}" ]]; then
    if [[ -d "$0.runfiles" ]]; then
        RUNFILES_DIR="$0.runfiles"
    else
        RUNFILES_DIR="$(cd "$(dirname "$0")" && pwd -P)/$(basename "$0").runfiles"
    fi
fi

RUNFILES_DIR="$(cd "$RUNFILES_DIR" && pwd -P)"
WORKSPACE_DIR="$RUNFILES_DIR/_main"

cd "$WORKSPACE_DIR"

{env_lines}

ANCHOR_LIB="$(pwd)/{anchor_lib}"
LIB_DIR="$(dirname "$ANCHOR_LIB")"

export DYLD_LIBRARY_PATH="${{LIB_DIR}}:${{DYLD_LIBRARY_PATH:-}}"
export LD_LIBRARY_PATH="${{LIB_DIR}}:${{LD_LIBRARY_PATH:-}}"

export MIRI_SYSROOT="$(pwd)/{sysroot_dir}"
export MIRIFLAGS="{miri_flags}"

RUSTC_ABS="$(pwd)/{rustc}"
CARGO_ABS="$(pwd)/{cargo}"
MIRI_ABS="$(pwd)/{miri_bin}"
CARGO_MIRI_ABS="$(pwd)/{cargo_miri_bin}"

TOOLS_DIR="$(mktemp -d)"
ln -sf "$RUSTC_ABS" "$TOOLS_DIR/rustc"
ln -sf "$CARGO_ABS" "$TOOLS_DIR/cargo"
ln -sf "$MIRI_ABS" "$TOOLS_DIR/miri"
ln -sf "$CARGO_MIRI_ABS" "$TOOLS_DIR/cargo-miri"

cat > "$TOOLS_DIR/rustup" << 'SHIM'
#!/usr/bin/env bash
echo "info: component 'rust-src' is up to date"
exit 0
SHIM
chmod +x "$TOOLS_DIR/rustup"

export PATH="${{TOOLS_DIR}}:$PATH"

CARGO_TEMP="$(mktemp -d)"
export CARGO_HOME="$CARGO_TEMP"

unset RUSTUP_TOOLCHAIN
unset RUSTUP_HOME

CARGO_WS_DIR="$RUNFILES_DIR/+miri+miri_cargo_workspace"

cd "$CARGO_WS_DIR"

"$CARGO_MIRI_ABS" miri {subcmd} \\
    -p {crate_name} \\
    --lib \\
    "$@" 2>&1

exit_code=$?

rm -rf "$TOOLS_DIR" "$CARGO_TEMP"

exit $exit_code
""".format(
        workspace = ctx.workspace_name,
        env_lines = env_lines,
        anchor_lib = anchor_lib.short_path,
        sysroot_dir = sysroot_dir.short_path,
        miri_flags = " ".join(miri_flags),
        miri_bin = miri_bin.short_path,
        cargo_miri_bin = cargo_miri_bin.short_path,
        rustc = rustc.short_path,
        cargo = cargo.short_path,
        edition = edition,
        crate_name = crate_name,
        subcmd = "test" if ctx.attr.test_mode else "run",
    )

    ctx.actions.write(
        output = runner,
        content = script,
        is_executable = True,
    )

    all_inputs = (
        srcs +
        cargo_workspace_files +
        [miri_bin, cargo_miri_bin, rustc, cargo, sysroot_dir] +
        miri_all_files +
        rustc_lib_files +
        rust_toolchain.all_files.to_list()
    )

    runfiles = ctx.runfiles(files = all_inputs)
    if DefaultInfo in target:
        runfiles = runfiles.merge(target[DefaultInfo].default_runfiles)

    return [DefaultInfo(
        executable = runner,
        files = depset([runner]),
        runfiles = runfiles,
    )]

miri_test_internal = rule(
    implementation = _miri_test_impl,
    cfg = miri_nightly_transition,
    attrs = {
        "target": attr.label(
            mandatory = True,
            providers = [DefaultInfo],
        ),
        "crate_name": attr.string(default = ""),
        "miri_flags": attr.string_list(
            default = [
                "-Zmiri-disable-isolation",
                "-Zmiri-symbolic-alignment-check",
                "-Zmiri-retag-fields",
            ],
        ),
        "test_mode": attr.bool(default = True),
        "edition": attr.string(default = "2021"),
        "env": attr.string_dict(default = {}),
        "_miri_bin": attr.label(
            default = "@miri//:miri_bin",
            allow_single_file = True,
            executable = True,
            cfg = "exec",
        ),
        "_cargo_miri_bin": attr.label(
            default = "@miri//:cargo_miri_bin",
            allow_single_file = True,
            executable = True,
            cfg = "exec",
        ),
        "_miri_all_files": attr.label(
            default = "@miri//:miri_all_files",
            allow_files = True,
        ),
        "_miri_sysroot": attr.label(
            default = "//miri:miri_sysroot",
            providers = [MiriSysrootInfo],
        ),
        "_cargo_workspace": attr.label(
            default = "@miri_cargo_workspace//:cargo_files",
            allow_files = True,
        ),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    },
    executable = True,
    toolchains = ["@rules_rust//rust:toolchain_type"],
    doc = "Internal: builds the Miri runner script with nightly transition.",
)
