"""Transition to force nightly toolchain for Miri rules."""

def _miri_nightly_transition_impl(settings, attr):
    return {
        "@rules_rust//rust/toolchain/channel:channel": "nightly",
    }

miri_nightly_transition = transition(
    implementation = _miri_nightly_transition_impl,
    inputs = [],
    outputs = [
        "@rules_rust//rust/toolchain/channel:channel",
    ],
)
