"""Public API for Miri rules."""

load("//miri:miri.bzl", "miri_test_internal")

_DEFAULT_MIRI_FLAGS = [
    "-Zmiri-disable-isolation",
    "-Zmiri-symbolic-alignment-check",
    "-Zmiri-retag-fields",
]

def rust_miri_test(name, target, miri_flags = None, tags = None, **kwargs):
    """Runs #[test] functions under Miri (cargo miri test)."""
    tags = list(tags or [])
    if "miri" not in tags:
        tags.append("miri")

    # Internal rule builds the runner script with nightly transition
    miri_test_internal(
        name = name + "_internal",
        target = target,
        test_mode = True,
        miri_flags = miri_flags or _DEFAULT_MIRI_FLAGS,
        tags = tags,
        testonly = True,
        **kwargs
    )

    # Wrap with sh_test for proper test discovery
    native.sh_test(
        name = name,
        srcs = [name + "_internal"],
        tags = tags,
        **kwargs
    )

def rust_miri_run(name, target, miri_flags = None, tags = None, **kwargs):
    """Runs a binary under Miri (cargo miri run)."""
    tags = list(tags or [])
    if "miri" not in tags:
        tags.append("miri")

    miri_test_internal(
        name = name + "_internal",
        target = target,
        test_mode = False,
        miri_flags = miri_flags or _DEFAULT_MIRI_FLAGS,
        tags = tags,
        testonly = True,
        **kwargs
    )

    native.sh_test(
        name = name,
        srcs = [name + "_internal"],
        tags = tags,
        **kwargs
    )
