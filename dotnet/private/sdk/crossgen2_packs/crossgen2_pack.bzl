load("@bazel_lib//lib:copy_file.bzl", "COPY_FILE_TOOLCHAINS", "copy_file_action")

".Net Crossgen2 Pack"

def _crossgen2_pack_impl(ctx):
    # This is a workaround because label settings require a default target
    # so we create a default target with `pack` set as None.
    if ctx.label.name == "empty_pack":
        # This is a default executable that is used when for some reason we can't transition to a specific crossgen2 pack.
        # This exectutable should never be run and thus it just fails with an error message.
        default_executable = ctx.actions.declare_file("crossgen.sh")
        ctx.actions.write(default_executable, "#!/usr/bin/env bash\n\necho \"Error: No crossgen2 pack selected. This should never happen.\"\n\nexit 1\n")
        return [DefaultInfo(executable = default_executable)]

    # Find crossgen2 executable in the pack
    # The crossgen2 tool is in the tools/ directory of the NuGet package
    # and the native files are in the same directory as the crossgen2 tool.
    crossgen2_file = None
    runfiles_files = []

    # We need to copy the crossgen2 executable and all the native files to the output directory
    # because Bazel does not allow rules to return exectuables that are not output by the rule.
    for f in ctx.attr.pack[DefaultInfo].files.to_list():
        # If the file ends with .so, .dylib, or .dll, add it to the list of native files
        if f.basename.endswith(".so") or f.basename.endswith(".dylib") or f.basename.endswith(".dll"):
            native_file = ctx.actions.declare_file("{}/{}".format(ctx.label.name, f.basename))
            copy_file_action(ctx, f, native_file)
            runfiles_files.append(native_file)

        # crossgen2 is the main executable (crossgen2 on unix, crossgen2.exe on windows)
        if f.basename.lower() == "crossgen2" or f.basename.lower() == "crossgen2.exe":
            crossgen2_file = f

    if crossgen2_file == None:
        fail("crossgen2 executable not found in crossgen2 pack")

    if len(runfiles_files) == 0:
        fail("no native files found in crossgen2 pack. Something is wrong with the pack.")

    crossgen2_executable = ctx.actions.declare_file("{}/{}".format(ctx.label.name, crossgen2_file.basename))
    copy_file_action(ctx, crossgen2_file, crossgen2_executable)

    # Return DefaultInfo with the crossgen2 executable and all required runtime files
    return [
        DefaultInfo(
            executable = crossgen2_executable,
            runfiles = ctx.runfiles(files = runfiles_files),
        ),
    ]

crossgen2_pack = rule(
    _crossgen2_pack_impl,
    doc = """.Net crossgen2 Pack""",
    attrs = {
        "pack": attr.label(
            doc = "The crossgen2 nuget package target",
        ),
    },
    executable = True,
    toolchains = COPY_FILE_TOOLCHAINS,
)
