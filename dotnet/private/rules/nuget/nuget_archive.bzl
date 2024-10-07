"NuGet Archive"

load(
    "@bazel_tools//tools/build_defs/repo:utils.bzl",
    "read_netrc",
    "read_user_netrc",
    "use_netrc",
)
load(
    "//dotnet/private:common.bzl",
    "COR_FRAMEWORKS",
    "FRAMEWORK_COMPATIBILITY",
    "NET_FRAMEWORKS",
    "STD_FRAMEWORKS",
    "get_highest_compatible_target_framework",
)
load(
    "//dotnet/private/sdk:rids.bzl",
    "RUNTIME_GRAPH",
)

def _is_windows(repository_ctx):
    """Returns true if the host operating system is windows."""
    os_name = repository_ctx.os.name.lower()
    if os_name.find("windows") != -1:
        return True
    return False

def _read_dir(repository_ctx, src_dir):
    """Returns a string with all files in a directory.

    Finds all files inside a directory, traversing subfolders and following
    symlinks. The returned string contains the full path of all files
    separated by line breaks.
    """
    if _is_windows(repository_ctx):
        src_dir = src_dir.replace("/", "\\")
        nuget_directory = repository_ctx.execute(["cmd.exe", "/c", "echo|set", "/p=%cd%"])
        find_result = repository_ctx.execute(["cmd.exe", "/c", "dir", src_dir, "/b", "/s", "/a-d"])

        # The output from the find command includes absolute paths so we strip the
        # current working directory from the paths
        result = find_result.stdout.replace(nuget_directory.stdout + "\\", "")

        # src_files will be used in genrule.outs where the paths must
        # use forward slashes.
        result = result.replace("\\", "/")
    else:
        find_result = repository_ctx.execute(["find", src_dir, "-follow", "-type", "f"])
        result = find_result.stdout
    return result

def _create_framework_select(name, group):
    if len(group) == 0:
        return None

    result = ["tfm_filegroup(\"%s\", {\n" % name]

    for (tfm, items) in group.items():
        result.append(' "')
        result.append(tfm)
        result.append('": [')
        result.append(",".join(["\n   \"{}\"".format(item) for item in items if not item.endswith("_._")]))
        result.append("],\n")

    result.append("})")

    return "".join(result)

def _create_rid_native_select(name, group):
    if len(group) == 0:
        return None

    result = ["rid_filegroup(\"%s\", {\n" % name]

    for (rid, items) in group.items():
        result.append(' "')
        result.append(rid)
        result.append('": [')
        result.append(",".join(["\n   \"{}\"".format(item) for item in items]))
        result.append("],\n")

    result.append("})")

    return "".join(result)

def _sanitize_path(file_path):
    # On linux the relative file path starts with ./
    if file_path.startswith("./"):
        return file_path[2:]

    return file_path

# We have encountered some packages that have non-standard TFM names
# and we replace the non-standard names with the standard names here
def _replace_non_standard_tfm(tfm):
    if tfm == "netstandard20":
        return "netstandard2.0"

    if tfm == "netstandard21":
        return "netstandard2.1"

    return tfm

# This function processes a package file that has the following format:
# <group>/<tfm>/<file>
def _process_group_with_tfm(groups, group_name, file):
    i = file.find("/")
    tfm_start = i + 1
    tfm_end = file.find("/", i + 1)
    tfm = _replace_non_standard_tfm(file[tfm_start:tfm_end])

    if tfm not in FRAMEWORK_COMPATIBILITY:
        return

    # If the folder is empty we do nothing
    if file.find("/", tfm_end + 1) != -1:
        return

    group = groups[group_name]

    if not group.get(tfm):
        group[tfm] = []

    # If the folder contains a _._ file we create the group but do not add the file to it
    # to indicate that there was an _._ file in the folder. The file indicates that the
    # package is compatible with the TFM.
    if file.endswith("_._"):
        return

    if not file.endswith(".dll") or file.endswith(".resources.dll"):
        return

    group[tfm].append(file)

    return

def _process_build_file(groups, file):
    i = file.find("/")
    tfm_start = i + 1
    tfm_end = file.find("/", i + 1)
    tfm = file[tfm_start:tfm_end]
    file_type = file[tfm_end + 1:file.find("/", tfm_end + 1)]

    # Handle .NETFramework
    if tfm == ".NETFramework":
        version_start = file.find("/", tfm_start) + 1
        version = file[version_start:file.find("/", version_start + 1)]
        tfm = version.replace("v", "net").replace(".", "")
        file_type = "ref"

    if tfm not in FRAMEWORK_COMPATIBILITY:
        return

    # See https://github.com/bazel-contrib/rules_dotnet/issues/405
    if not file.endswith(".dll") or file.endswith(".resources.dll") or file.endswith("System.EnterpriseServices.Thunk.dll") or file.endswith("System.EnterpriseServices.Wrapper.dll"):
        return

    group = groups["build"]

    if not group.get(tfm):
        group[tfm] = {
            "lib": [],
            "ref": [],
        }

    if file_type == "ref":
        group[tfm]["ref"].append(file)

    if file_type == "lib":
        group[tfm]["lib"].append(file)

    return

def _process_typeprovider_file(groups, file):
    if not file.endswith(".dll"):
        return

    parts = file.split("/")

    if len(parts) < 3:
        return

    tfm = parts[2]

    if tfm not in FRAMEWORK_COMPATIBILITY:
        return

    group = groups["typeproviders"]

    if not group.get(tfm):
        group[tfm] = []

    group[tfm].append(file)

    return

def _process_analyzer_file(groups, file):
    if (not file.endswith(".dll")) or file.endswith("resources.dll"):
        return

    group = groups["analyzers"]

    parts = file.split("/")

    # The path format is analyzers/{framework_name}{version}/{supported_architecture}/{supported_language}/{analyzer_name}.dll
    # Note: The only supported framework_name is `dotnet`

    # Note: The `supported_architecture` part is not properly handled yet see: https://github.com/dotnet/sdk/issues/20355
    # The tl;dr: Anaylzers can be built for different versions of roslyn and the `target_architecture` is strctured like this `roslyn<roslyn version>` e.g. `roslyn3.8`.
    # When a NuGet package contains folders under analyzers with the pattern, roslyn<major-version>.<minor-version>,
    # the folder with the highest version that is less than or equal to the current Microsoft.CodeAnalysis <major>.<minor> version should be used.
    # For now we add the latest version of the lowest version of of the package to stay the most compatible.

    # The analyzers can be either language specific or not. If they are not language specific the path will be analyzers/dotnet/{analyzer_name}.dll
    # if the analyzers are language specific the path will be analyzers/dotnet/{cs,vb,fs}/{analyzer_name}.dll
    if len(parts) == 3:
        group["dotnet"].append(file)
    elif len(parts) == 4:
        lang = parts[2]
        group["dotnet/{}".format(lang)].append(file)
    elif len(parts) == 5:
        lang = parts[3]
        supported_architecture = parts[2]

        # Use this as a marker for the lowest version of the dll
        if not group.get("dotnet/{}/lowest".format(lang)):
            group["dotnet/{}/lowest".format(lang)] = file
            group["dotnet/{}".format(lang)].append(file)
        else:
            # If the current version is lower than the version we have stored we replace it
            current_lowest_version = group["dotnet/{}/lowest".format(lang)].split("/")[2]
            if supported_architecture < current_lowest_version:
                group["dotnet/{}/lowest".format(lang, supported_architecture)] = file
                group["dotnet/{}".format(lang)].append(file)

    return

def _process_content_file(groups, file):
    group = groups["contentFiles"]
    group["any"].append(file)

    return

def _process_runtimes_file(groups, file):
    parts = file.split("/")

    if len(parts) < 2:
        return

    rid = parts[1]

    if rid not in RUNTIME_GRAPH:
        return

    if not groups.get("runtimes"):
        groups["runtimes"] = {}

    group = groups["runtimes"]

    if not group.get(rid):
        group[rid] = {
            "native": [],
            "lib": {},
        }

    if parts[2] == "native":
        group[rid]["native"].append(file)

    if parts[2] == "lib":
        tfm = parts[3]

        if tfm not in FRAMEWORK_COMPATIBILITY:
            return

        if not file.endswith(".dll") or file.endswith(".resources.dll"):
            return

        if not group[rid]["lib"].get(tfm):
            group[rid]["lib"][tfm] = []

        group[rid]["lib"][tfm].append(file)

    return

def _process_key_and_file(groups, key, file):
    # todo resource dlls
    if key == "lib":
        _process_group_with_tfm(groups, key, file)
    elif key == "ref":
        _process_group_with_tfm(groups, key, file)
    elif key == "analyzers":
        _process_analyzer_file(groups, file)
    elif key == "contentFiles":
        _process_content_file(groups, file)
    elif key == "typeproviders":
        _process_typeprovider_file(groups, file)
    elif key == "runtimes":
        _process_runtimes_file(groups, file)
    elif key == "build":
        _process_build_file(groups, file)

    return

def _get_package_urls(rctx, sources, auth, package_id, package_version):
    base_addresses = {}
    package_urls = []

    for source in sources:
        if base_addresses.get(source):
            continue

        # If the url ends with index.json we are dealing with a V3 NuGet feed
        # and the url schema for the package contents will be:
        # {base_address}/{lower_id}/{lower_version}/{lower_id}.{lower_version}.nupkg
        if source.endswith("index.json"):
            rctx.download(source, auth = auth, output = "index.json")
            index = json.decode(rctx.read("index.json"))
            rctx.delete("index.json")
            for resource in index["resources"]:
                if resource["@type"] == "PackageBaseAddress/3.0.0":
                    base_addresses[source] = resource["@id"]

                    package_urls.append(
                        "{base_address}{package_id}/{package_version}/{package_id}.{package_version}.nupkg".format(
                            base_address = resource["@id"] if resource["@id"].endswith("/") else resource["@id"] + "/",
                            package_id = package_id.lower(),
                            package_version = package_version.lower(),
                        ),
                    )
        else:
            # Else we expect the url to be a V2 NuGet feed and the url schema for the
            # package contents will be: {source}/package/{id}/{version}
            base_addresses[source] = source
            package_urls.append("{source}/package/{package_id}/{package_version}".format(source = source, package_id = package_id, package_version = package_version))

    return package_urls

def _get_auth_dict(ctx, netrc, urls):
    # Default to the user's netrc
    netrc = read_user_netrc(ctx)

    # If there is an netrc file declared for the specific package
    # we use that one instead of the user netrc
    if ctx.attr.netrc:
        netrc = read_netrc(ctx, ctx.attr.netrc)

    cred_dict = use_netrc(netrc, urls, {
        "type": "basic",
        "login": "<login>",
        "password": "<password>",
    })

    return cred_dict

def _nuget_archive_impl(ctx):
    # First get the auth dict for the package sources since the sources can be different than the
    # package base url when using NuGet V3 feeds.
    auth = _get_auth_dict(ctx, ctx.attr.netrc, ctx.attr.sources)
    urls = _get_package_urls(ctx, ctx.attr.sources, auth, ctx.attr.id, ctx.attr.version)

    # Then get the auth dict for the package base urls
    auth = _get_auth_dict(ctx, ctx.attr.netrc, urls)

    # We download it as .zip because ctx.exract reads the file extension to determine the archive type
    file_name = "%s.zip" % ctx.name
    nupkg_name = "%s.%s.nupkg" % (ctx.attr.id, ctx.attr.version)
    names = [nupkg_name]

    ctx.download(urls, output = file_name, integrity = ctx.attr.sha512, auth = auth)
    ctx.extract(archive = file_name)
    for name in names:
        ctx.symlink(file_name, name)

    all_files = sorted(_read_dir(ctx, ".").replace(str(ctx.path(".")) + "/", "").splitlines())

    # The NuGet package format
    groups = {
        # See https://learn.microsoft.com/en-us/nuget/guides/analyzers-conventions
        # Example: analyzers/dotnet/cs/System.Runtime.CSharp.Analyzers.dll
        "analyzers": {
            "dotnet": [],
            "dotnet/cs": [],
            "dotnet/fs": [],
            "dotnet/vb": [],
        },
        # See: https://devblogs.microsoft.com/nuget/nuget-contentfiles-demystified/
        # NB: Only the any group is supported at the moment
        "contentFiles": {
            "any": [],
        },
        # Format: lib/<TFM>/<assembly>.dll
        "lib": {},
        # Format: ref/<TFM>/<assembly>.dll
        "ref": {},
        # See https://github.com/fsharp/fslang-design/blob/main/tooling/FST-1003-loading-type-provider-design-time-components.md
        # Format: typeproviders/<TFM>/<assembly>.dll
        "typeproviders": {},
        # See https://docs.microsoft.com/en-us/nuget/create-packages/supporting-multiple-target-frameworks#architecture-specific-folders
        # Format: runtimes/<RID>/native/<assembly>.dll OR runtimes/<RID>/lib/<TFM>/<assembly>.dll
        "runtimes": {
        },
        # See: https://learn.microsoft.com/en-us/nuget/concepts/msbuild-props-and-targets#framework-specific-build-folder
        # Format: build/<TFM>/ref/<assembly>.dll OR build/<TFM>/lib/<assembly>.dll
        # NB: This folder could be tricky to support globally because packages can bring MSBuild targets with them and we don't support that
        #     currently we just blindly add the files to the lib or ref group depending on the folder name
        "build": {
        },
    }

    for file in all_files:
        file = _sanitize_path(file)
        i = file.find("/")
        key = file[:i]

        _process_key_and_file(groups, key, file)

    # Now that we have processed all the files we need to make sure that they are correctly set to be
    # either a runtime dependency or a compile time dependency. Dependency resolution in .Net is fun!

    ##########################################
    # Let's start with the compile time dlls
    # The rules are like this:
    # - If there are dlls for a TFM in the ref folder then they are a compile time dll
    # - If there are dlls for a TFM in the lib folder but not in the ref folder we know that
    #   the package is compatible with that TFM and the lib entry should be used as a compile time dll
    # - If there are dlls for a TFM in the ref folder under the build folder then they are a compile time dll
    ##########################################
    refs = {}

    for (tfm, files) in groups.get("ref").items():
        refs[tfm] = files

    for (tfm, files) in groups.get("lib").items():
        if tfm not in refs:
            refs[tfm] = files

    for (tfm, ref_or_lib) in groups.get("build").items():
        if ref_or_lib.get("ref"):
            if tfm not in refs:
                refs[tfm] = ref_or_lib.get("ref")
            else:
                refs[tfm].extend(ref_or_lib.get("ref"))

    ######################################
    # Now we move on to the runtime dlls
    # The rules are like this:
    # - If there are dlls for a TFM in the lib folder they are a runtime dll
    # - If there are dlls for a TFM in the ref folder but not in the lib folder we know that the
    #   package supports the TFM so we need to create an empty configuration for the TFM since
    #   files in the ref folder are never runtime dependencies
    # - If there are dlls for a TFM in the the typeproviders folder they are a runtime dll
    # - If there are dlls for a TFM in the the build folder they are a runtime dll
    # - If there are dlls for a TFM in the runtimes folder they are a runtime dll and should
    #   replace the dll in the toplevel lib folder for a the TFM and RID combination
    # - If there are files for an RID in the native folder under runtimes then they are runtime dependencies
    #   when the target platform is compatible with the RID
    #####################################
    libs = {}
    native = {}

    for (tfm, files) in groups.get("lib").items():
        libs[tfm] = files

    for (tfm, _) in groups.get("ref").items():
        if tfm not in libs:
            libs[tfm] = []

    for (tfm, files) in groups.get("typeproviders").items():
        if libs.get(tfm):
            libs[tfm].extend(files)
        else:
            libs[tfm] = files

    for (tfm, ref_or_lib) in groups.get("build").items():
        if ref_or_lib.get("lib"):
            if tfm not in libs:
                libs[tfm] = ref_or_lib.get("lib")
            else:
                libs[tfm].extend(ref_or_lib.get("lib"))

    for (rid, files_for_rid) in groups.get("runtimes").items():
        native[rid] = files_for_rid.get("native")
        for (tfm, tfm_files) in files_for_rid.get("lib").items():
            # We create a combined TFM and RID entry for the lib files
            # This entry will only be matched when the Bazel configuration
            # is configured to this exact RID and TFM combination
            combined_tfm_and_rid = "{}_{}".format(tfm, rid)
            libs[combined_tfm_and_rid] = tfm_files

    ctx.file("BUILD.bazel", r"""package(default_visibility = ["//visibility:public"])
exports_files(glob(["**"]))
load("@rules_dotnet//dotnet/private/rules/nuget:nuget_archive.bzl", "tfm_filegroup", "rid_filegroup")
""" + "\n".join([
        _create_framework_select("libs", libs) or "filegroup(name = \"libs\", srcs = [])",
        _create_framework_select("refs", refs) or "filegroup(name = \"refs\", srcs = [])",
        "filegroup(name = \"analyzers\", srcs = [%s])" % ",".join(["\n  \"%s\"" % a for a in groups.get("analyzers")["dotnet"]]),
        "filegroup(name = \"analyzers_csharp\", srcs = [%s])" % ",".join(["\n  \"%s\"" % a for a in groups.get("analyzers")["dotnet/cs"]]),
        "filegroup(name = \"analyzers_fsharp\", srcs = [%s])" % ",".join(["\n  \"%s\"" % a for a in groups.get("analyzers")["dotnet/fs"]]),
        "filegroup(name = \"analyzers_vb\", srcs = [%s])" % ",".join(["\n  \"%s\"" % a for a in groups.get("analyzers")["dotnet/vb"]]),
        "filegroup(name = \"data\", srcs = [])",
        _create_rid_native_select("native", native) or "filegroup(name = \"native\", srcs = [])",
        "filegroup(name = \"content_files\", srcs = [%s])" % ",".join(["\n  \"%s\"" % a for a in groups.get("contentFiles")["any"]]),
        "filegroup(name = \"files\", srcs = [%s])" % ",".join(["\n  \"%s\"" % _sanitize_path(a) for a in all_files]),
        "exports_files([\"%s\"])" % nupkg_name,
    ]))

nuget_archive = repository_rule(
    _nuget_archive_impl,
    attrs = {
        "sources": attr.string_list(),
        "netrc": attr.label(),
        "id": attr.string(),
        "version": attr.string(),
        "sha512": attr.string(),
    },
)

# This function is public because it's used by the nuget_archive repository rule.
# buildifier: disable=function-docstring
def tfm_filegroup(name, tfms):
    std = []
    net = []
    cor = []
    tfm_rids = {}

    for (tfm, value) in tfms.items():
        native.filegroup(
            name = "%s_%s_files" % (name, tfm),
            srcs = value,
            visibility = ["//visibility:public"],
        )
        parts = tfm.split("_")
        if len(parts) == 2:
            if tfm_rids.get(parts[0]):
                tfm_rids[parts[0]].append(parts[1])
            else:
                tfm_rids[parts[0]] = [parts[1]]
        elif tfm_rids.get(tfm):
            tfm_rids[tfm].append("default")
        else:
            tfm_rids[tfm] = ["default"]

    # If the TFM only exists without being bound to an RID we can
    # point the alias to the filegroup for the TFM. If the TFM is
    # bound to and RID we create the alias with a select statement
    # that selects on the RIDs that were bound to the TFM and we
    # then put the alias that points to the highest compatible TFM
    # as the default case.
    #
    # By setting the default case to the next highest compatible TFM we
    # make sure that we don't select on an TFM that only has RIDs
    # that are incompatible with the current configuration
    tfm_target_mapping = {}
    for (tfm, rids) in tfm_rids.items():
        if len(rids) == 1:
            actual = None
            if rids[0] == "default":
                actual = "%s_%s_files" % (name, tfm)
            else:
                actual = "%s_%s_%s_files" % (name, tfm, rids[0])
            native.alias(
                name = "%s_%s_alias" % (name, tfm),
                actual = actual,
                visibility = ["//visibility:public"],
            )
            tfm_target_mapping[tfm] = ":%s_%s_alias" % (name, tfm)
        else:
            map = {"@rules_dotnet//dotnet:rid_%s" % rid: ":%s_%s_%s_files" % (name, tfm, rid) for rid in rids if rid != "default"}

            if "default" in rids:
                map["//conditions:default"] = ":%s_%s_files" % (name, tfm)
            else:
                next_tfm = get_highest_compatible_target_framework(tfm, [t for t in tfm_rids.keys() if t != tfm])
                if next_tfm:
                    map["//conditions:default"] = ":%s_%s_alias" % (name, next_tfm)
            native.alias(
                name = "%s_%s_alias" % (name, tfm),
                actual = select(map),
                visibility = ["//visibility:public"],
            )

        tfm_target_mapping[tfm] = ":%s_%s_alias" % (name, tfm)

    for (tfm, target) in tfm_target_mapping.items():
        original_tfm = tfm
        parts = tfm.split("_")
        if len(parts) == 2:
            tfm = parts[0]

        if tfm in COR_FRAMEWORKS and (tfm not in cor):
            cor.append((original_tfm, target))
        elif tfm in STD_FRAMEWORKS and (tfm not in std):
            std.append((original_tfm, target))
        elif tfm in NET_FRAMEWORKS and (tfm not in net):
            net.append((original_tfm, target))
        else:
            fail("unknown framework %s" % tfm)

    # there can be a conflict between std and (cor/net) packages where both have a
    # candidate but none encapsulates the other. If this can be the case we
    # bootstrap different filegroups for each framework type (cor, std, net) and
    # determine which filegroup to hit using alias().
    if std and (net or cor):
        native.alias(
            name = "%s_std" % name,
            actual = select({"@rules_dotnet//dotnet:tfm_%s" % tfm: target for (tfm, target) in std}),
            visibility = ["//visibility:public"],
        )

        if net:
            native.alias(
                name = "%s_net" % name,
                actual = select({"@rules_dotnet//dotnet:tfm_%s" % tfm: target for (tfm, target) in net}),
                visibility = ["//visibility:public"],
            )

        if cor:
            native.alias(
                name = "%s_cor" % name,
                actual = select({"@rules_dotnet//dotnet:tfm_%s" % tfm: target for (tfm, target) in cor}),
                visibility = ["//visibility:public"],
            )

        return native.alias(
            name = name,
            actual = select({
                # targeting net(core)
                "@rules_dotnet//dotnet:tfm_netcoreapp1.0": (":%s_cor" % name) if cor else (":%s_std" % name),
                # targeting netframework
                "@rules_dotnet//dotnet:tfm_net11": (":%s_net" % name) if net else (":%s_std" % name),
                # targeting netstandard
                "//conditions:default": (":%s_std" % name),
            }),
            visibility = ["//visibility:public"],
        )

    return native.alias(
        name = name,
        actual = select({"@rules_dotnet//dotnet:tfm_%s" % tfm: target for (tfm, target) in tfm_target_mapping.items()}),
        visibility = ["//visibility:public"],
    )

# This function is public because it's used by the nuget_archive repository rule.
# buildifier: disable=function-docstring
def rid_filegroup(name, files_per_rid):
    map = {"@rules_dotnet//dotnet:rid_%s" % rid: files for (rid, files) in files_per_rid.items()}
    map["//conditions:default"] = []
    return native.filegroup(
        name = name,
        srcs = select(map),
        visibility = ["//visibility:public"],
    )
