"""Stands in for the packs of a .NET release that the SDK predates."""

load("//dotnet/private/sdk:releases.bzl", "tfm_channel")

def _sdk_too_old_impl(ctx):
    major = tfm_channel(ctx.attr.target_framework).split(".")[0]

    fail("{} is .NET {}, which .NET SDK {} predates. Building for it needs a .NET {} SDK or newer: see `dotnet.toolchain` in MODULE.bazel.".format(
        ctx.attr.target_framework,
        major,
        ctx.attr.sdk_version,
        major,
    ))

sdk_too_old = rule(
    _sdk_too_old_impl,
    doc = """Fails, saying which SDK a target framework needs.

rules_dotnet declares .NET releases ahead of time, so the pack tables built
while loading name the packs of releases newer than the SDK. Each of those is
one of these, so that building for such a release says what it needs rather
than that a package is missing.""",
    attrs = {
        "sdk_version": attr.string(
            doc = "The SDK the packs would have come from.",
            mandatory = True,
        ),
        "target_framework": attr.string(
            doc = "The framework the packs are for.",
            mandatory = True,
        ),
    },
)
