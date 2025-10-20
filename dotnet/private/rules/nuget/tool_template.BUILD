dotnet_tool(
    name = "tool_{NAME}",
    entrypoint = {{
{ENTRYPOINT_BY_TFM}
    }},
    runner = {{
{RUNNER_BY_TFM}
    }},
    target_frameworks = {TFMS},
    deps = "@{PREFIX}.{ID_LOWER}.v{VERSION}//:tools",
)
