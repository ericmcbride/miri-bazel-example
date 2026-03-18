"""Bzlmod module extension for Miri toolchain."""

load("//miri:repositories.bzl", "miri_register")

def _miri_impl(mctx):
    for mod in mctx.modules:
        for toolchain in mod.tags.toolchain:
            miri_register(
                nightly_date = toolchain.nightly_date,
                miri_sha256s = toolchain.miri_sha256s,
                rust_src_sha256 = toolchain.rust_src_sha256,
            )

_toolchain_tag = tag_class(
    attrs = {
        "nightly_date": attr.string(mandatory = True),
        "miri_sha256s": attr.string_dict(default = {}),
        "rust_src_sha256": attr.string(default = ""),
    },
)

miri = module_extension(
    implementation = _miri_impl,
    tag_classes = {
        "toolchain": _toolchain_tag,
    },
)
