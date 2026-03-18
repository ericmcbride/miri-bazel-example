"""Repository rules that download Miri, rust-src, and collect cargo workspace files."""

_MIRI_DIST_URL = "https://static.rust-lang.org/dist/{date}/miri-nightly-{triple}.tar.xz"
_RUST_SRC_URL = "https://static.rust-lang.org/dist/{date}/rust-src-nightly.tar.xz"

_SUPPORTED_TRIPLES = [
    "aarch64-apple-darwin",
    "x86_64-unknown-linux-gnu",
    "aarch64-unknown-linux-gnu",
]

def _miri_platform_repo_impl(rctx):
    triple = rctx.attr.triple
    nightly_date = rctx.attr.nightly_date

    url = _MIRI_DIST_URL.format(date = nightly_date, triple = triple)

    rctx.report_progress("Downloading Miri for {} ({})".format(triple, nightly_date))

    rctx.download_and_extract(
        url = url,
        sha256 = rctx.attr.sha256,
        stripPrefix = "miri-nightly-{}".format(triple),
    )

    rctx.file("BUILD.bazel", content = """\
package(default_visibility = ["//visibility:public"])

filegroup(
    name = "miri_bin",
    srcs = ["miri-preview/bin/miri"],
)

filegroup(
    name = "cargo_miri_bin",
    srcs = ["miri-preview/bin/cargo-miri"],
)

filegroup(
    name = "all_files",
    srcs = glob(["**/*"]),
)

exports_files([
    "miri-preview/bin/miri",
    "miri-preview/bin/cargo-miri",
])
""")

miri_platform_repo = repository_rule(
    implementation = _miri_platform_repo_impl,
    attrs = {
        "nightly_date": attr.string(mandatory = True),
        "triple": attr.string(mandatory = True),
        "sha256": attr.string(default = ""),
    },
)

def _rust_src_repo_impl(rctx):
    nightly_date = rctx.attr.nightly_date
    url = _RUST_SRC_URL.format(date = nightly_date)

    rctx.report_progress("Downloading rust-src ({})".format(nightly_date))

    rctx.download_and_extract(
        url = url,
        sha256 = rctx.attr.sha256,
        stripPrefix = "rust-src-nightly",
    )

    rctx.file("BUILD.bazel", content = """\
package(default_visibility = ["//visibility:public"])

filegroup(
    name = "rust_src",
    srcs = glob(["rust-src/**"]),
)

filegroup(
    name = "all_files",
    srcs = glob(["**/*"]),
)
""")

rust_src_repo = repository_rule(
    implementation = _rust_src_repo_impl,
    attrs = {
        "nightly_date": attr.string(mandatory = True),
        "sha256": attr.string(default = ""),
    },
)

def _miri_hub_repo_impl(rctx):
    rctx.file("BUILD.bazel", content = """\
package(default_visibility = ["//visibility:public"])

config_setting(
    name = "macos_aarch64",
    constraint_values = [
        "@platforms//os:macos",
        "@platforms//cpu:aarch64",
    ],
)

config_setting(
    name = "linux_x86_64",
    constraint_values = [
        "@platforms//os:linux",
        "@platforms//cpu:x86_64",
    ],
)

config_setting(
    name = "linux_aarch64",
    constraint_values = [
        "@platforms//os:linux",
        "@platforms//cpu:aarch64",
    ],
)

alias(
    name = "miri_bin",
    actual = select({
        ":macos_aarch64": "@miri_aarch64-apple-darwin//:miri_bin",
        ":linux_x86_64": "@miri_x86_64-unknown-linux-gnu//:miri_bin",
        ":linux_aarch64": "@miri_aarch64-unknown-linux-gnu//:miri_bin",
    }),
)

alias(
    name = "cargo_miri_bin",
    actual = select({
        ":macos_aarch64": "@miri_aarch64-apple-darwin//:cargo_miri_bin",
        ":linux_x86_64": "@miri_x86_64-unknown-linux-gnu//:cargo_miri_bin",
        ":linux_aarch64": "@miri_aarch64-unknown-linux-gnu//:cargo_miri_bin",
    }),
)

alias(
    name = "miri_all_files",
    actual = select({
        ":macos_aarch64": "@miri_aarch64-apple-darwin//:all_files",
        ":linux_x86_64": "@miri_x86_64-unknown-linux-gnu//:all_files",
        ":linux_aarch64": "@miri_aarch64-unknown-linux-gnu//:all_files",
    }),
)

alias(
    name = "rust_src",
    actual = "@miri_rust_src//:rust_src",
)
""")

miri_hub_repo = repository_rule(
    implementation = _miri_hub_repo_impl,
    attrs = {
        "nightly_date": attr.string(mandatory = True),
    },
)

def _cargo_workspace_repo_impl(rctx):
    """Symlinks all Cargo and source files from the workspace."""

    cargo_toml_path = str(rctx.path(Label("//:Cargo.toml")))
    workspace_root = str(rctx.path(Label("//:Cargo.toml")).dirname)
    out_dir = str(rctx.path("."))

    rctx.symlink(Label("//:Cargo.toml"), "Cargo.toml")
    rctx.symlink(Label("//:Cargo.lock"), "Cargo.lock")

    setup_script = str(rctx.path(Label("//miri:setup_cargo_workspace.sh")))

    result = rctx.execute(
        ["sh", setup_script, cargo_toml_path, workspace_root, out_dir],
        timeout = 30,
    )

    if result.return_code != 0:
        fail("Failed to setup cargo workspace: stdout={} stderr={}".format(
            result.stdout, result.stderr,
        ))

cargo_workspace_repo = repository_rule(
    implementation = _cargo_workspace_repo_impl,
    local = True,
    doc = "Collects all Cargo workspace and source files for cargo miri.",
)

def miri_register(nightly_date, miri_sha256s = {}, rust_src_sha256 = ""):
    """Registers all Miri repositories."""

    for triple in _SUPPORTED_TRIPLES:
        miri_platform_repo(
            name = "miri_{}".format(triple),
            nightly_date = nightly_date,
            triple = triple,
            sha256 = miri_sha256s.get(triple, ""),
        )

    rust_src_repo(
        name = "miri_rust_src",
        nightly_date = nightly_date,
        sha256 = rust_src_sha256,
    )

    miri_hub_repo(
        name = "miri",
        nightly_date = nightly_date,
    )

    cargo_workspace_repo(
        name = "miri_cargo_workspace",
    )
