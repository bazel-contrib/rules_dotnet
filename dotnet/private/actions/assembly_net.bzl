load("@rules_mono//dotnet/private:actions/assembly_common.bzl", "emit_assembly_common")

def emit_assembly_net(
        dotnet,
        name,
        srcs,
        deps = None,
        out = None,
        resources = None,
        executable = True,
        defines = None,
        unsafe = False,
        data = None,
        keyfile = None,
        subdir = "./",
        target_framework = "",
        nowarn = None,
        langversion = "latest",
        version = (0, 0, 0, 0, "")):
    return emit_assembly_common(
        kind = "net",
        dotnet = dotnet,
        name = name,
        srcs = srcs,
        deps = deps,
        out = out,
        resources = resources,
        executable = executable,
        defines = defines,
        unsafe = unsafe,
        data = data,
        keyfile = keyfile,
        subdir = subdir,
        target_framework = target_framework,
        nowarn = nowarn,
        langversion = langversion,
        version = version,
    )
