# rules_miri — Bazel Rules for Miri

Run [Miri](https://github.com/rust-lang/miri) (Rust's undefined behavior detector) as Bazel test targets in a Cargo workspace.

Please note this is a POC and I would not use this anywhere.  Theres alot of cleanup that needs to happen across the board.

## Features

- **Zero config** — `bazel test //crates/core:core_miri` just works
- **Automatic nightly toolchain** — Miri targets use nightly via Bazel transitions, no `--config` flags needed
- **Hermetic** — Miri binary, rust-src, and sysroot are all downloaded/built by Bazel
- **Cached sysroot** — The Miri sysroot (slow to build) is cached as a Bazel action output
- **Multi-platform** — Supports macOS ARM64, Linux x86_64, and Linux ARM64

## Quick Start

### 1. Add to `MODULE.bazel`

```python
bazel_dep(name = "rules_rust", version = "0.54.1")
bazel_dep(name = "bazel_skylib", version = "1.7.1")
bazel_dep(name = "platforms", version = "0.0.10")

# Rust toolchain — must include nightly with the same date as Miri
rust = use_extension("@rules_rust//rust:extensions.bzl", "rust")
rust.toolchain(
    edition = "2021",
    versions = ["nightly/2025-12-01", "1.88.0"],
)
use_repo(rust, "rust_toolchains")
register_toolchains("@rust_toolchains//:all")

# Miri
miri = use_extension("//miri:extensions.bzl", "miri")
miri.toolchain(nightly_date = "2025-12-01")
use_repo(
    miri,
    "miri",
    "miri_rust_src",
    "miri_aarch64-apple-darwin",
    "miri_x86_64-unknown-linux-gnu",
    "miri_aarch64-unknown-linux-gnu",
    "miri_cargo_workspace",
)
```

> **Important**: The `nightly_date` in `miri.toolchain()` must exactly match the nightly version in `rust.toolchain()`. Even one day difference will cause `librustc_driver` hash mismatches.
We will need to fix this long term

### 2. Add Miri test targets

```python
load("@rules_rust//rust:defs.bzl", "rust_library", "rust_test")
load("//miri:defs.bzl", "rust_miri_test")

rust_library(
    name = "my_lib",
    srcs = ["src/lib.rs"],
    edition = "2021",
)

rust_test(
    name = "my_lib_test",
    crate = ":my_lib",
)

# Miri test — runs #[test] functions under Miri
rust_miri_test(
    name = "my_lib_miri",
    target = ":my_lib",
)
```

### 3. Run

```bash
# Run Miri tests — no flags needed
bazel test //crates/core:core_miri

# Run all tests (including Miri)
bazel test //...

# See failure output
bazel test //crates/core:core_miri --test_output=streamed
```

### 4. Recommended `.bazelrc`

```
# Show test output on failures
test --test_output=errors
```

## How It Works

```
┌─────────────────────────────────────────────────────────┐
│ MODULE.bazel                                            │
│   miri.toolchain(nightly_date = "2025-12-01")           │
└─────────────────────┬───────────────────────────────────┘
                      │
          ┌───────────┼───────────────┐
          ▼           ▼               ▼
   ┌──────────┐ ┌──────────┐ ┌──────────────────┐
   │ @miri//  │ │ rust-src │ │ cargo_workspace  │
   │ miri bin │ │ download │ │ repo (symlinks   │
   │ per-plat │ │          │ │ Cargo.toml + .rs)│
   └────┬─────┘ └────┬─────┘ └────────┬─────────┘
        │             │                │
        ▼             ▼                │
   ┌─────────────────────────┐         │
   │ //miri:miri_sysroot     │         │
   │ (cargo miri setup)      │         │
   │ Builds .rlib with MIR   │         │
   │ [nightly transition]    │         │
   └────────────┬────────────┘         │
                │                      │
                ▼                      ▼
   ┌─────────────────────────────────────────┐
   │ rust_miri_test / rust_miri_run          │
   │                                         │
   │ macro creates:                          │
   │   *_internal  (nightly transition)      │
   │   *           (sh_test wrapper)         │
   │                                         │
   │ Runs: cargo miri test -p <crate> --lib  │
   └─────────────────────────────────────────┘
```

### Build flow

1. **Module extension** downloads Miri binary (per-platform), `rust-src`, and creates a repo with all Cargo workspace files
2. **`miri_sysroot` rule** runs `cargo miri setup` to compile `libstd`/`libcore` with `-Zalways-encode-mir`, producing `.rlib` files Miri can interpret. This is cached after the first build.
3. **`rust_miri_test` macro** creates a shell script that:
   - Sets up `DYLD_LIBRARY_PATH`/`LD_LIBRARY_PATH` for `librustc_driver`
   - Sets `MIRI_SYSROOT` to the pre-built sysroot
   - Puts `rustc`, `cargo`, `miri`, `cargo-miri` on `PATH`
   - Fakes `rustup` to prevent network calls
   - Runs `cargo miri test -p <crate_name> --lib`
4. **Nightly transition** on both the sysroot and test internal target ensures the nightly Rust toolchain is used regardless of the user's default config

### Why `cargo miri` instead of standalone `miri`?

The standalone `miri` binary cannot be invoked directly — it requires `cargo miri` to:
- Properly set up the `MIRI_BE_RUSTC` environment for compilation
- Resolve crate dependencies and `--extern` flags
- Handle the sysroot validation
- Manage the two-phase compilation (compile with MIR, then interpret)

Newer versions of Miri explicitly error with: *"Note that directly invoking the miri binary is not supported; please use cargo miri instead."*

### Why symlink the workspace?

`cargo miri test` is a Cargo subcommand that needs:
- The workspace root `Cargo.toml` and `Cargo.lock`
- All workspace member `Cargo.toml` files
- All `.rs` source files

Bazel's sandbox doesn't include files from other packages by default. The `cargo_workspace_repo` repository rule symlinks all Cargo manifests and Rust source files into a single repo that `cargo` can navigate as a normal workspace.

## API Reference

### `rust_miri_test`

Runs `#[test]` functions under Miri (`cargo miri test --lib`).

```python
rust_miri_test(
    name = "my_lib_miri",
    target = ":my_lib",
    # Optional:
    miri_flags = ["-Zmiri-disable-isolation", "-Zmiri-symbolic-alignment-check"],
    env = {"MY_VAR": "value"},
    crate_name = "my_lib",  # Auto-detected from CrateInfo
)
```

| Attribute | Type | Default | Description |
|-----------|------|---------|-------------|
| `target` | label | required | The `rust_library` or `rust_binary` target to test |
| `miri_flags` | string_list | `["-Zmiri-disable-isolation", "-Zmiri-symbolic-alignment-check", "-Zmiri-retag-fields"]` | Flags passed via `MIRIFLAGS` |
| `env` | string_dict | `{}` | Extra environment variables |
| `crate_name` | string | auto | Cargo crate name (auto-detected from `CrateInfo`) |

### `rust_miri_run`

Runs a binary's `fn main()` under Miri (`cargo miri run`).

```python
rust_miri_run(
    name = "my_app_miri",
    target = ":my_app",
)
```

Same attributes as `rust_miri_test`.

## File Structure

```
miri/
├── BUILD.bazel             # miri_sysroot target
├── defs.bzl                # Public API: rust_miri_test, rust_miri_run
├── miri.bzl                # Core rule implementation
├── miri_sysroot.bzl        # Sysroot build rule (cargo miri setup)
├── transition.bzl          # Nightly toolchain transition
├── extensions.bzl          # Bzlmod module extension
├── repositories.bzl        # Repository rules (download Miri, rust-src, etc.)
└── setup_cargo_workspace.sh # Shell script to symlink workspace files
```

## Troubleshooting

### `librustc_driver` not found

The Miri nightly date must exactly match the `rules_rust` nightly toolchain date. Check both:

```bash
grep "nightly" MODULE.bazel
```

### Sysroot rebuilds every time

The sysroot is keyed on its inputs. If the toolchain config changes (e.g., switching between stable and nightly), Bazel rebuilds it. This is expected on the first run after a config change. Subsequent runs are cached.

### `cargo metadata` errors

Ensure all workspace member `Cargo.toml` files and source files are being symlinked. Check:

```bash
ls bazel-bin/crates/core/core_miri.runfiles/+miri+miri_cargo_workspace/
```

### Tests excluded by filters

If `bazel test //...` skips Miri targets, check `.bazelrc` for `--test_tag_filters=-miri`. Remove it or run Miri targets explicitly.

## TODOs

- [ ] **Reuse `rules_rust` `crate_universe` data** — Currently we symlink the entire Cargo workspace into a separate repo via `setup_cargo_workspace.sh`. Ideally we would reuse the workspace metadata that `crate_universe` already parsed, avoiding the need to duplicate Cargo manifests and source files. This would also eliminate the shell script for Cargo.toml parsing.

- [ ] **Explore standalone `miri` invocation** — The current approach uses `cargo miri` because standalone `miri` requires manual `--extern` flag construction and sysroot wiring that newer Miri versions reject. If future Miri versions re-support direct invocation, we could bypass Cargo entirely and make the rule more Bazel-native (no Cargo workspace needed, deps from `CrateInfo`).

- [ ] **Pre-built Miri sysroot caching** — The sysroot build (`cargo miri setup`) takes ~10-15 seconds and downloads crates from crates.io. Consider distributing pre-built sysroots per nightly date or caching them in a remote cache.

- [ ] **Windows support** — Add `x86_64-pc-windows-msvc` platform support. The `DYLD_LIBRARY_PATH` / `LD_LIBRARY_PATH` approach would need to be replaced with `PATH` on Windows.

- [ ] **`rust-src` from `rules_rust`** — Currently `rust-src` is downloaded separately via `http_archive`. If `rules_rust` adds support for `extra_rustup_components` (e.g., `rust-src`), we should use that instead.

- [ ] **Reduce `use_repo` boilerplate** — The user currently needs to list all per-platform repos in `use_repo()`. Explore hub-repo patterns or Bzlmod improvements to reduce this to `use_repo(miri, "miri")`.

- [ ] **Integration test targets** — Support `--tests` and `--bins` flags for `cargo miri test` in addition to `--lib`, to run integration tests and binary targets under Miri.

- [ ] **Remote execution compatibility** — The current `DYLD_LIBRARY_PATH` approach is macOS-specific. Verify and fix for remote execution environments where the execution platform may differ from the host.

- [ ] **Doc-test support** — Currently doc-tests are skipped (`--lib` flag). The `--test-runtool` error with doc-tests needs investigation.

- [ ] **Configurable sysroot `CARGO_HOME`** — The sysroot build downloads crates to a temp `CARGO_HOME`. For air-gapped environments, support pointing to a pre-populated registry.
