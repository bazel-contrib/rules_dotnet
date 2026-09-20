"""Scoped CSS: per-component stylesheets.

A `Foo.razor.css` beside `Foo.razor` applies only to that component. The SDK
implements this by hashing the stylesheet's path into a scope identifier,
rewriting every selector to carry it, and bundling the results. Those three
steps ship as MSBuild tasks, and `//dotnet/private/tools/scoped_css` runs the
SDK's own copies rather than reimplementing a CSS parser.

The scope reaches two places: the rewritten CSS, and the Razor source
generator, which reads it from an analyzer config. The scope is a hash and
Starlark cannot compute one, so the tool writes that config too. It lands in the
Razor staging directory while the `TargetPath` config sits one level above it,
because Roslyn rejects two analyzer configs in a single directory.
"""

load("//dotnet/private/rules/csharp/actions:razor.bzl", "RAZOR_STAGING_DIR", "target_path")

# What MSBuild names a rewritten stylesheet and each kind of bundle.
_REWRITTEN_SUFFIX = ".rz.scp.css"
_PROJECT_BUNDLE_SUFFIX = ".bundle.scp.css"
_APPLICATION_BUNDLE_SUFFIX = ".styles.css"

_TASKS_ASSEMBLY = "Microsoft.NET.Sdk.StaticWebAssets.Tasks.dll"

def _tasks_assembly(toolchain, label):
    tasks = toolchain.static_web_assets_tasks
    for file in tasks.files.to_list() if tasks else []:
        if file.basename == _TASKS_ASSEMBLY:
            return file

    fail(
        "the resolved .NET toolchain provides no %s, so %s cannot compile scoped CSS.\n" % (
            _TASKS_ASSEMBLY,
            label,
        ) +
        "The SDK is expected to carry it under " +
        "Sdks/Microsoft.NET.Sdk.StaticWebAssets/tasks.",
    )

def scoped_css_action(
        actions,
        label,
        out_dir,
        assembly_name,
        bundle_base_path,
        is_application,
        scoped_css_srcs,
        project_bundles,
        tool,
        toolchain):
    """Rewrites per-component stylesheets and bundles them.

    Args:
      actions: The rule's `ctx.actions`.
      label: The label of the target being compiled.
      out_dir: The target's output directory prefix.
      assembly_name: The target's assembly name, which names the bundle.
      bundle_base_path: Where the target's assets are served from.
      is_application: Whether this target produces the application bundle that
        imports its libraries' bundles, rather than a bundle of its own.
      scoped_css_srcs: The `.razor.css` sources.
      project_bundles: The serving paths of the referenced libraries' bundles.
      tool: The `scoped_css` tool.
      toolchain: The resolved .NET toolchain.

    Returns:
      A struct with the `bundle` and the `scope_config` the Razor compile has to
      read.
    """
    tasks = _tasks_assembly(toolchain, label)

    bundle = actions.declare_file("{}/{}{}".format(
        out_dir,
        assembly_name,
        _APPLICATION_BUNDLE_SUFFIX if is_application else _PROJECT_BUNDLE_SUFFIX,
    ))
    scope_config = actions.declare_file("{}/{}/razor.cssscope.editorconfig".format(out_dir, RAZOR_STAGING_DIR))

    files = []
    outputs = [bundle, scope_config]
    for src in scoped_css_srcs:
        css_relative_path = target_path(src.short_path, label)

        # `Foo.razor.css` belongs to `Foo.razor`, and the generator looks the
        # scope up by the component's path.
        razor_relative_path = css_relative_path[:-len(".css")]

        rewritten = actions.declare_file("{}/scopedcss/{}{}".format(
            out_dir,
            razor_relative_path,
            _REWRITTEN_SUFFIX,
        ))
        outputs.append(rewritten)

        files.append(struct(
            razorRelativePath = razor_relative_path,
            cssRelativePath = css_relative_path,
            source = src.path,
            rewritten = rewritten.path,
        ))

    request = actions.declare_file("{}/scoped_css_request.json".format(out_dir))
    actions.write(
        output = request,
        content = json.encode(struct(
            tasksAssembly = tasks.path,
            targetName = assembly_name,
            bundleBasePath = bundle_base_path,
            bundle = bundle.path,
            scopeConfig = scope_config.path,
            projectBundles = project_bundles,
            files = files,
        )),
    )

    args = actions.args()
    args.add(request)

    actions.run(
        mnemonic = "ScopedCss",
        progress_message = "Rewriting scoped CSS for " + label.name,
        executable = tool.files_to_run,
        arguments = [args],
        inputs = depset(
            direct = scoped_css_srcs + [request],
            transitive = [toolchain.static_web_assets_tasks.files],
        ),
        outputs = outputs,
    )

    return struct(bundle = bundle, scope_config = scope_config)
