load(
    "@io_bazel_rules_dotnet//dotnet/private:context.bzl",
    "dotnet_context",
)
load(
    "@io_bazel_rules_dotnet//dotnet/private:providers.bzl",
    "DotnetLibrary",
    "DotnetResource",
)

_TEMPLATE_NUNIT_MONO = """
echo "Executing $0"

export PATH=/usr/bin:/bin:$PATH

if [[ -f "$0.runfiles/MANIFEST" ]]; then
export RUNFILES_MANIFEST_FILE="$0.runfiles/MANIFEST"
elif [[ -f "$0.runfiles_manifest" ]]; then
export RUNFILES_MANIFEST_FILE="$0.runfiles_manifest"
elif [[ -n "$RUNFILES_DIR" ]]; then
export RUNFILES_MANIFEST_FILE="$RUNFILES_DIR/MANIFEST"
fi

echo "Using for MANIFEST $RUNFILES_MANIFEST_FILE"
DIR=$(dirname $RUNFILES_MANIFEST_FILE)

PREPARELINKPRG="{prepare}"
LAUNCHERPATH="{launch}"
EXEBASENAME="{exebasename}"

PREPARE=`awk '{{if ($1 ~ "{prepare}") {{print $2;exit}} }}' $RUNFILES_MANIFEST_FILE`
$PREPARE $RUNFILES_MANIFEST_FILE

if [[ "$OSTYPE" == "darwin"* ]]; then
    READLINK=greadlink
else
    READLINK=readlink
fi

MONOPRG=`$READLINK -f $DIR/mono`
echo "Using $MONOPRG and $XML_OUTPUT_FILE"
"$MONOPRG" $DIR/{testlauncher} -xml=$XML_OUTPUT_FILE $DIR/$EXEBASENAME "$@"
result=$?
exit $result
"""

_TEMPLATE_NUNIT_NET = """
echo "Executing $0"

export PATH=/usr/bin:/bin:$PATH

if [[ -f "$0.runfiles/MANIFEST" ]]; then
export RUNFILES_MANIFEST_FILE="$0.runfiles/MANIFEST"
elif [[ -f "$0.runfiles_manifest" ]]; then
export RUNFILES_MANIFEST_FILE="$0.runfiles_manifest"
elif [[ -n "$RUNFILES_DIR" ]]; then
export RUNFILES_MANIFEST_FILE="$RUNFILES_DIR/MANIFEST"
fi

echo "Using for MANIFEST $RUNFILES_MANIFEST_FILE"
DIR=$(dirname $RUNFILES_MANIFEST_FILE)

PREPARELINKPRG="{prepare}"
LAUNCHERPATH="{launch}"
EXEBASENAME="{exebasename}"

PATH=/usr/bin:/bin:$PATH
PREPARE=`awk '{{if ($1 ~ "{prepare}") {{print $2;exit}} }}' $RUNFILES_MANIFEST_FILE`

$PREPARE $RUNFILES_MANIFEST_FILE

$DIR/{testlauncher} --result=`cygpath -w $XML_OUTPUT_FILE` $DIR/$EXEBASENAME "$@"
result=$?
exit $result
"""

_TEMPLATE_NUNIT3_NET = """
echo "Executing $0"

export PATH=/usr/bin:/bin:$PATH

if [[ -f "$0.runfiles/MANIFEST" ]]; then
export RUNFILES_MANIFEST_FILE="$0.runfiles/MANIFEST"
elif [[ -f "$0.runfiles_manifest" ]]; then
export RUNFILES_MANIFEST_FILE="$0.runfiles_manifest"
elif [[ -n "$RUNFILES_DIR" ]]; then
export RUNFILES_MANIFEST_FILE="$RUNFILES_DIR/MANIFEST"
fi

echo "Using for MANIFEST $RUNFILES_MANIFEST_FILE"
DIR=$(dirname $RUNFILES_MANIFEST_FILE)

PREPARELINKPRG="{prepare}"
LAUNCHERPATH="{launch}"
EXEBASENAME="{exebasename}"

PATH=/usr/bin:/bin:$PATH
PREPARE=`awk '{{if ($1 ~ "{prepare}") {{print $2;exit}} }}' $RUNFILES_MANIFEST_FILE`

$PREPARE $RUNFILES_MANIFEST_FILE

$DIR/{testlauncher} --result=`cygpath -w $XML_OUTPUT_FILE`\;transform=`cygpath -w $DIR/{xslt}` $DIR/$EXEBASENAME "$@"
result=$?
exit $result
"""

_TEMPLATE_XUNIT_CORE = """
echo "Executing $0"

export PATH=/usr/bin:/bin:$PATH

if [[ -f "$0.runfiles/MANIFEST" ]]; then
export RUNFILES_MANIFEST_FILE="$0.runfiles/MANIFEST"
elif [[ -f "$0.runfiles_manifest" ]]; then
export RUNFILES_MANIFEST_FILE="$0.runfiles_manifest"
elif [[ -n "$RUNFILES_DIR" ]]; then
export RUNFILES_MANIFEST_FILE="$RUNFILES_DIR/MANIFEST"
fi

echo "Using for MANIFEST $RUNFILES_MANIFEST_FILE"
DIR=$(dirname $RUNFILES_MANIFEST_FILE)

PREPARELINKPRG="{prepare}"
LAUNCHERPATH="{launch}"
EXEBASENAME="{exebasename}"

PATH=/usr/bin:/bin:$PATH
PREPARE=`awk '{{if ($1 ~ "{prepare}") {{print $2;exit}} }}' $RUNFILES_MANIFEST_FILE`

$PREPARE $RUNFILES_MANIFEST_FILE

if [[ "$OSTYPE" == "darwin"* ]]; then
    READLINK=greadlink
else
    READLINK=readlink
fi

DOTNETPRG=`$READLINK -f $DIR/dotnet`
echo "Using $DOTNETPRG and $XML_OUTPUT_FILE"

if [[ "$OS" == "Windows"* ]]; then
    OUT=`cygpath -w $XML_OUTPUT_FILE`
else
    OUT=$XML_OUTPUT_FILE
fi

"$DOTNETPRG" $DIR/{testlauncher} $DIR/$EXEBASENAME -junit $OUT "$@"
result=$?
exit $result
"""

_TEMPLATE_XUNIT_NET = """
echo "Executing $0"

export PATH=/usr/bin:/bin:$PATH

if [[ -f "$0.runfiles/MANIFEST" ]]; then
export RUNFILES_MANIFEST_FILE="$0.runfiles/MANIFEST"
elif [[ -f "$0.runfiles_manifest" ]]; then
export RUNFILES_MANIFEST_FILE="$0.runfiles_manifest"
elif [[ -n "$RUNFILES_DIR" ]]; then
export RUNFILES_MANIFEST_FILE="$RUNFILES_DIR/MANIFEST"
fi

echo "Using for MANIFEST $RUNFILES_MANIFEST_FILE"
DIR=$(dirname $RUNFILES_MANIFEST_FILE)

PREPARELINKPRG="{prepare}"
LAUNCHERPATH="{launch}"
EXEBASENAME="{exebasename}"

PATH=/usr/bin:/bin:$PATH
PREPARE=`awk '{{if ($1 ~ "{prepare}") {{print $2;exit}} }}' $RUNFILES_MANIFEST_FILE`

$PREPARE $RUNFILES_MANIFEST_FILE

echo "Using $XML_OUTPUT_FILE"

if [[ "$OS" == "Windows"* ]]; then
    OUT=`cygpath -w $XML_OUTPUT_FILE`
else
    OUT=$XML_OUTPUT_FILE
fi

$DIR/{testlauncher} $DIR/$EXEBASENAME -junit $OUT "$@"
result=$?
exit $result
"""

_TEMPLATE_XUNIT_MONO = """
echo "Executing $0"

export PATH=/usr/bin:/bin:$PATH

if [[ -f "$0.runfiles/MANIFEST" ]]; then
export RUNFILES_MANIFEST_FILE="$0.runfiles/MANIFEST"
elif [[ -f "$0.runfiles_manifest" ]]; then
export RUNFILES_MANIFEST_FILE="$0.runfiles_manifest"
elif [[ -n "$RUNFILES_DIR" ]]; then
export RUNFILES_MANIFEST_FILE="$RUNFILES_DIR/MANIFEST"
fi

echo "Using for MANIFEST $RUNFILES_MANIFEST_FILE"
DIR=$(dirname $RUNFILES_MANIFEST_FILE)

PREPARELINKPRG="{prepare}"
LAUNCHERPATH="{launch}"
EXEBASENAME="{exebasename}"

PATH=/usr/bin:/bin:$PATH
PREPARE=`awk '{{if ($1 ~ "{prepare}") {{print $2;exit}} }}' $RUNFILES_MANIFEST_FILE`

$PREPARE $RUNFILES_MANIFEST_FILE

if [[ "$OSTYPE" == "darwin"* ]]; then
    READLINK=greadlink
else
    READLINK=readlink
fi

PRG=`$READLINK -f $DIR/mono`
echo "Using $DOTNETPRG and $XML_OUTPUT_FILE"

if [[ "$OS" == "Windows"* ]]; then
    OUT=`cygpath -w $XML_OUTPUT_FILE`
else
    OUT=$XML_OUTPUT_FILE
fi

"$PRG" $DIR/{testlauncher} $DIR/$EXEBASENAME -junit $OUT "$@"
result=$?
exit $result
"""

def _unit_test(ctx):
    dotnet = dotnet_context(ctx)
    name = ctx.label.name

    # Handle case of empty toolchain on linux and darwin
    if dotnet.assembly == None:
        empty = dotnet.declare_file(dotnet, path = "empty.sh")
        dotnet.actions.write(output = empty, content = "echo '.net not supported on this platform'")
        library = dotnet.new_library(dotnet = dotnet)
        return [library, DefaultInfo(executable = empty)]

    library = dotnet.assembly(
        dotnet,
        name = name,
        srcs = ctx.attr.srcs,
        deps = ctx.attr.deps,
        resources = ctx.attr.resources,
        out = ctx.attr.out,
        defines = ctx.attr.defines,
        unsafe = ctx.attr.unsafe,
        data = ctx.attr.data,
        executable = False,
    )

    testlauncher = ctx.attr.testlauncher.files.to_list()[0].basename

    launcher = ctx.actions.declare_file("{}.bash".format(name))
    content = ctx.attr._template.format(
        prepare = ctx.attr._manifest_prep.files.to_list()[0].basename,
        launch = launcher.path,
        exebasename = library.result.basename,
        testlauncher = testlauncher,
        xslt = ctx.attr._xslt.files.to_list()[0].basename,
    )
    ctx.actions.write(output = launcher, content = content, is_executable = True)

    files = []
    if launcher != None:
        files += [launcher]
    if dotnet.runner != None:
        files += [dotnet.runner]
    files += ctx.attr._manifest_prep.files.to_list() + ctx.attr.native_deps.files.to_list() + ctx.attr._xslt.files.to_list()

    runfiles = ctx.runfiles(files = files, transitive_files = library.runfiles)
    test_launcher_runfiles = ctx.runfiles(files = [ctx.attr.testlauncher[DotnetLibrary].result], transitive_files = ctx.attr.testlauncher[DotnetLibrary].runfiles)
    runfiles = runfiles.merge(test_launcher_runfiles)

    return [
        library,
        DefaultInfo(
            files = depset([library.result, launcher]),
            runfiles = runfiles,
            executable = launcher,
        ),
    ]

dotnet_nunit_test = rule(
    _unit_test,
    attrs = {
        "deps": attr.label_list(providers = [DotnetLibrary]),
        "resources": attr.label_list(providers = [DotnetResource]),
        "srcs": attr.label_list(allow_files = [".cs"]),
        "out": attr.string(),
        "defines": attr.string_list(),
        "unsafe": attr.bool(default = False),
        "data": attr.label_list(allow_files = True),
        "dotnet_context_data": attr.label(default = Label("@io_bazel_rules_dotnet//:dotnet_context_data")),
        "_manifest_prep": attr.label(default = Label("//dotnet/tools/manifest_prep")),
        "native_deps": attr.label(default = Label("@dotnet_sdk//:native_deps")),
        "testlauncher": attr.label(default = "@nunit2//:nunit-console-runner-exe", providers = [DotnetLibrary]),
        "_template": attr.string(default = _TEMPLATE_NUNIT_MONO),
        "_xslt": attr.label(default = Label("@io_bazel_rules_dotnet//tools/converttests:n3.xslt"), allow_files = True),
    },
    toolchains = ["@io_bazel_rules_dotnet//dotnet:toolchain"],
    executable = True,
    test = True,
)

net_nunit_test = rule(
    _unit_test,
    attrs = {
        "deps": attr.label_list(providers = [DotnetLibrary]),
        "resources": attr.label_list(providers = [DotnetResource]),
        "srcs": attr.label_list(allow_files = [".cs"]),
        "out": attr.string(),
        "defines": attr.string_list(),
        "unsafe": attr.bool(default = False),
        "data": attr.label_list(allow_files = True),
        "dotnet_context_data": attr.label(default = Label("@io_bazel_rules_dotnet//:net_context_data")),
        "_manifest_prep": attr.label(default = Label("//dotnet/tools/manifest_prep")),
        "native_deps": attr.label(default = Label("@net_sdk//:native_deps")),
        "testlauncher": attr.label(default = "@nunit2//:net.nunit-console-runner-exe", providers = [DotnetLibrary]),
        "_template": attr.string(default = _TEMPLATE_NUNIT_NET),
        "_xslt": attr.label(default = Label("@io_bazel_rules_dotnet//tools/converttests:n3.xslt"), allow_files = True),
    },
    toolchains = ["@io_bazel_rules_dotnet//dotnet:toolchain_net"],
    executable = True,
    test = True,
)

net_nunit3_test = rule(
    _unit_test,
    attrs = {
        "deps": attr.label_list(providers = [DotnetLibrary]),
        "resources": attr.label_list(providers = [DotnetResource]),
        "srcs": attr.label_list(allow_files = [".cs"]),
        "out": attr.string(),
        "defines": attr.string_list(),
        "unsafe": attr.bool(default = False),
        "data": attr.label_list(allow_files = True),
        "dotnet_context_data": attr.label(default = Label("@io_bazel_rules_dotnet//:net_context_data")),
        "_manifest_prep": attr.label(default = Label("//dotnet/tools/manifest_prep")),
        "native_deps": attr.label(default = Label("@net_sdk//:native_deps")),
        "testlauncher": attr.label(default = "@nunit3_consolerunner//:nunit3.console.exe", providers = [DotnetLibrary]),
        "_template": attr.string(default = _TEMPLATE_NUNIT3_NET),
        "_xslt": attr.label(default = Label("@io_bazel_rules_dotnet//tools/converttests:n3.xslt"), allow_files = True),
    },
    toolchains = ["@io_bazel_rules_dotnet//dotnet:toolchain_net"],
    executable = True,
    test = True,
)

core_xunit_test = rule(
    _unit_test,
    attrs = {
        "deps": attr.label_list(providers = [DotnetLibrary]),
        "resources": attr.label_list(providers = [DotnetResource]),
        "srcs": attr.label_list(allow_files = [".cs"]),
        "out": attr.string(),
        "defines": attr.string_list(),
        "unsafe": attr.bool(default = False),
        "data": attr.label_list(allow_files = True),
        "dotnet_context_data": attr.label(default = Label("@io_bazel_rules_dotnet//:core_context_data")),
        "_manifest_prep": attr.label(default = Label("//dotnet/tools/manifest_prep")),
        "native_deps": attr.label(default = Label("@core_sdk//:native_deps")),
        "testlauncher": attr.label(default = "@xunit//:xunit.console", providers = [DotnetLibrary]),
        "_template": attr.string(default = _TEMPLATE_XUNIT_CORE),
        "_xslt": attr.label(default = Label("@io_bazel_rules_dotnet//tools/converttests:n3.xslt"), allow_files = True),
    },
    toolchains = ["@io_bazel_rules_dotnet//dotnet:toolchain_core"],
    executable = True,
    test = True,
)

net_xunit_test = rule(
    _unit_test,
    attrs = {
        "deps": attr.label_list(providers = [DotnetLibrary]),
        "resources": attr.label_list(providers = [DotnetResource]),
        "srcs": attr.label_list(allow_files = [".cs"]),
        "out": attr.string(),
        "defines": attr.string_list(),
        "unsafe": attr.bool(default = False),
        "data": attr.label_list(allow_files = True),
        "dotnet_context_data": attr.label(default = Label("@io_bazel_rules_dotnet//:net_context_data")),
        "_manifest_prep": attr.label(default = Label("//dotnet/tools/manifest_prep")),
        "native_deps": attr.label(default = Label("@net_sdk//:native_deps")),
        "testlauncher": attr.label(default = "@xunit.runner.console//:net472_net_tool", providers = [DotnetLibrary]),
        "_template": attr.string(default = _TEMPLATE_XUNIT_NET),
        "_xslt": attr.label(default = Label("@io_bazel_rules_dotnet//tools/converttests:n3.xslt"), allow_files = True),
    },
    toolchains = ["@io_bazel_rules_dotnet//dotnet:toolchain_net"],
    executable = True,
    test = True,
)

dotnet_xunit_test = rule(
    _unit_test,
    attrs = {
        "deps": attr.label_list(providers = [DotnetLibrary]),
        "resources": attr.label_list(providers = [DotnetResource]),
        "srcs": attr.label_list(allow_files = [".cs"]),
        "out": attr.string(),
        "defines": attr.string_list(),
        "unsafe": attr.bool(default = False),
        "data": attr.label_list(allow_files = True),
        "dotnet_context_data": attr.label(default = Label("@io_bazel_rules_dotnet//:dotnet_context_data")),
        "_manifest_prep": attr.label(default = Label("//dotnet/tools/manifest_prep")),
        "native_deps": attr.label(default = Label("@dotnet_sdk//:native_deps")),
        "testlauncher": attr.label(default = "@xunit.runner.console//:mono_tool", providers = [DotnetLibrary]),
        "_template": attr.string(default = _TEMPLATE_XUNIT_MONO),
        "_xslt": attr.label(default = Label("@io_bazel_rules_dotnet//tools/converttests:n3.xslt"), allow_files = True),
    },
    toolchains = ["@io_bazel_rules_dotnet//dotnet:toolchain"],
    executable = True,
    test = True,
)
