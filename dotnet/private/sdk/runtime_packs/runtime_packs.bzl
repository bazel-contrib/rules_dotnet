"GENERATED BY SDK GENERATOR"

load("//dotnet/private/sdk/runtime_packs:runtime_pack.bzl", "runtime_pack")

# buildifier: disable=unnamed-macro
def runtime_packs():
    """runtime packs"""

    runtime_pack(name = "default_netcoreapp3.0_linux-x64", packs = ["@dotnet.runtime_packs//microsoft.netcore.app.runtime.linux-x64.v3.0.3"], target_framework = "netcoreapp3.0", runtime_identifier = "linux-x64")
    runtime_pack(name = "default_netcoreapp3.0_linux-arm64", packs = ["@dotnet.runtime_packs//microsoft.netcore.app.runtime.linux-arm64.v3.0.3"], target_framework = "netcoreapp3.0", runtime_identifier = "linux-arm64")
    runtime_pack(name = "default_netcoreapp3.0_linux-musl-x64", packs = ["@dotnet.runtime_packs//microsoft.netcore.app.runtime.linux-musl-x64.v3.0.3"], target_framework = "netcoreapp3.0", runtime_identifier = "linux-musl-x64")
    runtime_pack(name = "default_netcoreapp3.0_linux-musl-arm64", packs = ["@dotnet.runtime_packs//microsoft.netcore.app.runtime.linux-musl-arm64.v3.0.3"], target_framework = "netcoreapp3.0", runtime_identifier = "linux-musl-arm64")
    runtime_pack(name = "default_netcoreapp3.0_osx-x64", packs = ["@dotnet.runtime_packs//microsoft.netcore.app.runtime.osx-x64.v3.0.3"], target_framework = "netcoreapp3.0", runtime_identifier = "osx-x64")
    runtime_pack(name = "default_netcoreapp3.0_win-x64", packs = ["@dotnet.runtime_packs//microsoft.netcore.app.runtime.win-x64.v3.0.3"], target_framework = "netcoreapp3.0", runtime_identifier = "win-x64")
    runtime_pack(name = "default_netcoreapp3.0_win-arm64", packs = ["@dotnet.runtime_packs//microsoft.netcore.app.runtime.win-arm64.v3.0.3"], target_framework = "netcoreapp3.0", runtime_identifier = "win-arm64")
    runtime_pack(name = "default_netcoreapp3.1_linux-x64", packs = ["@dotnet.runtime_packs//microsoft.netcore.app.runtime.linux-x64.v3.1.32"], target_framework = "netcoreapp3.1", runtime_identifier = "linux-x64")
    runtime_pack(name = "default_netcoreapp3.1_linux-arm64", packs = ["@dotnet.runtime_packs//microsoft.netcore.app.runtime.linux-arm64.v3.1.32"], target_framework = "netcoreapp3.1", runtime_identifier = "linux-arm64")
    runtime_pack(name = "default_netcoreapp3.1_linux-musl-x64", packs = ["@dotnet.runtime_packs//microsoft.netcore.app.runtime.linux-musl-x64.v3.1.32"], target_framework = "netcoreapp3.1", runtime_identifier = "linux-musl-x64")
    runtime_pack(name = "default_netcoreapp3.1_linux-musl-arm64", packs = ["@dotnet.runtime_packs//microsoft.netcore.app.runtime.linux-musl-arm64.v3.1.32"], target_framework = "netcoreapp3.1", runtime_identifier = "linux-musl-arm64")
    runtime_pack(name = "default_netcoreapp3.1_osx-x64", packs = ["@dotnet.runtime_packs//microsoft.netcore.app.runtime.osx-x64.v3.1.32"], target_framework = "netcoreapp3.1", runtime_identifier = "osx-x64")
    runtime_pack(name = "default_netcoreapp3.1_win-x64", packs = ["@dotnet.runtime_packs//microsoft.netcore.app.runtime.win-x64.v3.1.32"], target_framework = "netcoreapp3.1", runtime_identifier = "win-x64")
    runtime_pack(name = "default_netcoreapp3.1_win-arm64", packs = ["@dotnet.runtime_packs//microsoft.netcore.app.runtime.win-arm64.v3.1.32"], target_framework = "netcoreapp3.1", runtime_identifier = "win-arm64")
    runtime_pack(name = "default_net5.0_linux-x64", packs = ["@dotnet.runtime_packs//microsoft.netcore.app.runtime.linux-x64.v5.0.17"], target_framework = "net5.0", runtime_identifier = "linux-x64")
    runtime_pack(name = "default_net5.0_linux-arm64", packs = ["@dotnet.runtime_packs//microsoft.netcore.app.runtime.linux-arm64.v5.0.17"], target_framework = "net5.0", runtime_identifier = "linux-arm64")
    runtime_pack(name = "default_net5.0_linux-musl-x64", packs = ["@dotnet.runtime_packs//microsoft.netcore.app.runtime.linux-musl-x64.v5.0.17"], target_framework = "net5.0", runtime_identifier = "linux-musl-x64")
    runtime_pack(name = "default_net5.0_linux-musl-arm64", packs = ["@dotnet.runtime_packs//microsoft.netcore.app.runtime.linux-musl-arm64.v5.0.17"], target_framework = "net5.0", runtime_identifier = "linux-musl-arm64")
    runtime_pack(name = "default_net5.0_osx-x64", packs = ["@dotnet.runtime_packs//microsoft.netcore.app.runtime.osx-x64.v5.0.17"], target_framework = "net5.0", runtime_identifier = "osx-x64")
    runtime_pack(name = "default_net5.0_win-x64", packs = ["@dotnet.runtime_packs//microsoft.netcore.app.runtime.win-x64.v5.0.17"], target_framework = "net5.0", runtime_identifier = "win-x64")
    runtime_pack(name = "default_net5.0_win-arm64", packs = ["@dotnet.runtime_packs//microsoft.netcore.app.runtime.win-arm64.v5.0.17"], target_framework = "net5.0", runtime_identifier = "win-arm64")
    runtime_pack(name = "default_net6.0_linux-x64", packs = ["@dotnet.runtime_packs//microsoft.netcore.app.runtime.linux-x64.v6.0.36"], target_framework = "net6.0", runtime_identifier = "linux-x64")
    runtime_pack(name = "default_net6.0_linux-arm64", packs = ["@dotnet.runtime_packs//microsoft.netcore.app.runtime.linux-arm64.v6.0.36"], target_framework = "net6.0", runtime_identifier = "linux-arm64")
    runtime_pack(name = "default_net6.0_linux-musl-x64", packs = ["@dotnet.runtime_packs//microsoft.netcore.app.runtime.linux-musl-x64.v6.0.36"], target_framework = "net6.0", runtime_identifier = "linux-musl-x64")
    runtime_pack(name = "default_net6.0_linux-musl-arm64", packs = ["@dotnet.runtime_packs//microsoft.netcore.app.runtime.linux-musl-arm64.v6.0.36"], target_framework = "net6.0", runtime_identifier = "linux-musl-arm64")
    runtime_pack(name = "default_net6.0_osx-x64", packs = ["@dotnet.runtime_packs//microsoft.netcore.app.runtime.osx-x64.v6.0.36"], target_framework = "net6.0", runtime_identifier = "osx-x64")
    runtime_pack(name = "default_net6.0_osx-arm64", packs = ["@dotnet.runtime_packs//microsoft.netcore.app.runtime.osx-arm64.v6.0.36"], target_framework = "net6.0", runtime_identifier = "osx-arm64")
    runtime_pack(name = "default_net6.0_win-x64", packs = ["@dotnet.runtime_packs//microsoft.netcore.app.runtime.win-x64.v6.0.36"], target_framework = "net6.0", runtime_identifier = "win-x64")
    runtime_pack(name = "default_net6.0_win-arm64", packs = ["@dotnet.runtime_packs//microsoft.netcore.app.runtime.win-arm64.v6.0.36"], target_framework = "net6.0", runtime_identifier = "win-arm64")
    runtime_pack(name = "default_net7.0_linux-x64", packs = ["@dotnet.runtime_packs//microsoft.netcore.app.runtime.linux-x64.v7.0.20"], target_framework = "net7.0", runtime_identifier = "linux-x64")
    runtime_pack(name = "default_net7.0_linux-arm64", packs = ["@dotnet.runtime_packs//microsoft.netcore.app.runtime.linux-arm64.v7.0.20"], target_framework = "net7.0", runtime_identifier = "linux-arm64")
    runtime_pack(name = "default_net7.0_linux-musl-x64", packs = ["@dotnet.runtime_packs//microsoft.netcore.app.runtime.linux-musl-x64.v7.0.20"], target_framework = "net7.0", runtime_identifier = "linux-musl-x64")
    runtime_pack(name = "default_net7.0_linux-musl-arm64", packs = ["@dotnet.runtime_packs//microsoft.netcore.app.runtime.linux-musl-arm64.v7.0.20"], target_framework = "net7.0", runtime_identifier = "linux-musl-arm64")
    runtime_pack(name = "default_net7.0_osx-x64", packs = ["@dotnet.runtime_packs//microsoft.netcore.app.runtime.osx-x64.v7.0.20"], target_framework = "net7.0", runtime_identifier = "osx-x64")
    runtime_pack(name = "default_net7.0_osx-arm64", packs = ["@dotnet.runtime_packs//microsoft.netcore.app.runtime.osx-arm64.v7.0.20"], target_framework = "net7.0", runtime_identifier = "osx-arm64")
    runtime_pack(name = "default_net7.0_win-x64", packs = ["@dotnet.runtime_packs//microsoft.netcore.app.runtime.win-x64.v7.0.20"], target_framework = "net7.0", runtime_identifier = "win-x64")
    runtime_pack(name = "default_net7.0_win-arm64", packs = ["@dotnet.runtime_packs//microsoft.netcore.app.runtime.win-arm64.v7.0.20"], target_framework = "net7.0", runtime_identifier = "win-arm64")
    runtime_pack(name = "default_net8.0_linux-x64", packs = ["@dotnet.runtime_packs//microsoft.netcore.app.runtime.linux-x64.v8.0.14"], target_framework = "net8.0", runtime_identifier = "linux-x64")
    runtime_pack(name = "default_net8.0_linux-arm64", packs = ["@dotnet.runtime_packs//microsoft.netcore.app.runtime.linux-arm64.v8.0.14"], target_framework = "net8.0", runtime_identifier = "linux-arm64")
    runtime_pack(name = "default_net8.0_linux-musl-x64", packs = ["@dotnet.runtime_packs//microsoft.netcore.app.runtime.linux-musl-x64.v8.0.14"], target_framework = "net8.0", runtime_identifier = "linux-musl-x64")
    runtime_pack(name = "default_net8.0_linux-musl-arm64", packs = ["@dotnet.runtime_packs//microsoft.netcore.app.runtime.linux-musl-arm64.v8.0.14"], target_framework = "net8.0", runtime_identifier = "linux-musl-arm64")
    runtime_pack(name = "default_net8.0_osx-x64", packs = ["@dotnet.runtime_packs//microsoft.netcore.app.runtime.osx-x64.v8.0.14"], target_framework = "net8.0", runtime_identifier = "osx-x64")
    runtime_pack(name = "default_net8.0_osx-arm64", packs = ["@dotnet.runtime_packs//microsoft.netcore.app.runtime.osx-arm64.v8.0.14"], target_framework = "net8.0", runtime_identifier = "osx-arm64")
    runtime_pack(name = "default_net8.0_win-x64", packs = ["@dotnet.runtime_packs//microsoft.netcore.app.runtime.win-x64.v8.0.14"], target_framework = "net8.0", runtime_identifier = "win-x64")
    runtime_pack(name = "default_net8.0_win-arm64", packs = ["@dotnet.runtime_packs//microsoft.netcore.app.runtime.win-arm64.v8.0.14"], target_framework = "net8.0", runtime_identifier = "win-arm64")
    runtime_pack(name = "default_net9.0_linux-x64", packs = ["@dotnet.runtime_packs//microsoft.netcore.app.runtime.linux-x64.v9.0.3"], target_framework = "net9.0", runtime_identifier = "linux-x64")
    runtime_pack(name = "default_net9.0_linux-arm64", packs = ["@dotnet.runtime_packs//microsoft.netcore.app.runtime.linux-arm64.v9.0.3"], target_framework = "net9.0", runtime_identifier = "linux-arm64")
    runtime_pack(name = "default_net9.0_linux-musl-x64", packs = ["@dotnet.runtime_packs//microsoft.netcore.app.runtime.linux-musl-x64.v9.0.3"], target_framework = "net9.0", runtime_identifier = "linux-musl-x64")
    runtime_pack(name = "default_net9.0_linux-musl-arm64", packs = ["@dotnet.runtime_packs//microsoft.netcore.app.runtime.linux-musl-arm64.v9.0.3"], target_framework = "net9.0", runtime_identifier = "linux-musl-arm64")
    runtime_pack(name = "default_net9.0_osx-x64", packs = ["@dotnet.runtime_packs//microsoft.netcore.app.runtime.osx-x64.v9.0.3"], target_framework = "net9.0", runtime_identifier = "osx-x64")
    runtime_pack(name = "default_net9.0_osx-arm64", packs = ["@dotnet.runtime_packs//microsoft.netcore.app.runtime.osx-arm64.v9.0.3"], target_framework = "net9.0", runtime_identifier = "osx-arm64")
    runtime_pack(name = "default_net9.0_win-x64", packs = ["@dotnet.runtime_packs//microsoft.netcore.app.runtime.win-x64.v9.0.3"], target_framework = "net9.0", runtime_identifier = "win-x64")
    runtime_pack(name = "default_net9.0_win-arm64", packs = ["@dotnet.runtime_packs//microsoft.netcore.app.runtime.win-arm64.v9.0.3"], target_framework = "net9.0", runtime_identifier = "win-arm64")
    runtime_pack(name = "web_netcoreapp3.0_linux-x64", packs = ["@dotnet.runtime_packs//microsoft.aspnetcore.app.runtime.linux-x64.v3.0.3", "@dotnet.runtime_packs//microsoft.netcore.app.runtime.linux-x64.v3.0.3"], target_framework = "netcoreapp3.0", runtime_identifier = "linux-x64")
    runtime_pack(name = "web_netcoreapp3.0_linux-arm64", packs = ["@dotnet.runtime_packs//microsoft.aspnetcore.app.runtime.linux-arm64.v3.0.3", "@dotnet.runtime_packs//microsoft.netcore.app.runtime.linux-arm64.v3.0.3"], target_framework = "netcoreapp3.0", runtime_identifier = "linux-arm64")
    runtime_pack(name = "web_netcoreapp3.0_linux-musl-x64", packs = ["@dotnet.runtime_packs//microsoft.aspnetcore.app.runtime.linux-musl-x64.v3.0.3", "@dotnet.runtime_packs//microsoft.netcore.app.runtime.linux-musl-x64.v3.0.3"], target_framework = "netcoreapp3.0", runtime_identifier = "linux-musl-x64")
    runtime_pack(name = "web_netcoreapp3.0_linux-musl-arm64", packs = ["@dotnet.runtime_packs//microsoft.aspnetcore.app.runtime.linux-musl-arm64.v3.0.3", "@dotnet.runtime_packs//microsoft.netcore.app.runtime.linux-musl-arm64.v3.0.3"], target_framework = "netcoreapp3.0", runtime_identifier = "linux-musl-arm64")
    runtime_pack(name = "web_netcoreapp3.0_osx-x64", packs = ["@dotnet.runtime_packs//microsoft.aspnetcore.app.runtime.osx-x64.v3.0.3", "@dotnet.runtime_packs//microsoft.netcore.app.runtime.osx-x64.v3.0.3"], target_framework = "netcoreapp3.0", runtime_identifier = "osx-x64")
    runtime_pack(name = "web_netcoreapp3.0_win-x64", packs = ["@dotnet.runtime_packs//microsoft.aspnetcore.app.runtime.win-x64.v3.0.3", "@dotnet.runtime_packs//microsoft.netcore.app.runtime.win-x64.v3.0.3"], target_framework = "netcoreapp3.0", runtime_identifier = "win-x64")
    runtime_pack(name = "web_netcoreapp3.1_linux-x64", packs = ["@dotnet.runtime_packs//microsoft.aspnetcore.app.runtime.linux-x64.v3.1.32", "@dotnet.runtime_packs//microsoft.netcore.app.runtime.linux-x64.v3.1.32"], target_framework = "netcoreapp3.1", runtime_identifier = "linux-x64")
    runtime_pack(name = "web_netcoreapp3.1_linux-arm64", packs = ["@dotnet.runtime_packs//microsoft.aspnetcore.app.runtime.linux-arm64.v3.1.32", "@dotnet.runtime_packs//microsoft.netcore.app.runtime.linux-arm64.v3.1.32"], target_framework = "netcoreapp3.1", runtime_identifier = "linux-arm64")
    runtime_pack(name = "web_netcoreapp3.1_linux-musl-x64", packs = ["@dotnet.runtime_packs//microsoft.aspnetcore.app.runtime.linux-musl-x64.v3.1.32", "@dotnet.runtime_packs//microsoft.netcore.app.runtime.linux-musl-x64.v3.1.32"], target_framework = "netcoreapp3.1", runtime_identifier = "linux-musl-x64")
    runtime_pack(name = "web_netcoreapp3.1_linux-musl-arm64", packs = ["@dotnet.runtime_packs//microsoft.aspnetcore.app.runtime.linux-musl-arm64.v3.1.32", "@dotnet.runtime_packs//microsoft.netcore.app.runtime.linux-musl-arm64.v3.1.32"], target_framework = "netcoreapp3.1", runtime_identifier = "linux-musl-arm64")
    runtime_pack(name = "web_netcoreapp3.1_osx-x64", packs = ["@dotnet.runtime_packs//microsoft.aspnetcore.app.runtime.osx-x64.v3.1.32", "@dotnet.runtime_packs//microsoft.netcore.app.runtime.osx-x64.v3.1.32"], target_framework = "netcoreapp3.1", runtime_identifier = "osx-x64")
    runtime_pack(name = "web_netcoreapp3.1_win-x64", packs = ["@dotnet.runtime_packs//microsoft.aspnetcore.app.runtime.win-x64.v3.1.32", "@dotnet.runtime_packs//microsoft.netcore.app.runtime.win-x64.v3.1.32"], target_framework = "netcoreapp3.1", runtime_identifier = "win-x64")
    runtime_pack(name = "web_netcoreapp3.1_win-arm64", packs = ["@dotnet.runtime_packs//microsoft.aspnetcore.app.runtime.win-arm64.v3.1.32", "@dotnet.runtime_packs//microsoft.netcore.app.runtime.win-arm64.v3.1.32"], target_framework = "netcoreapp3.1", runtime_identifier = "win-arm64")
    runtime_pack(name = "web_net5.0_linux-x64", packs = ["@dotnet.runtime_packs//microsoft.aspnetcore.app.runtime.linux-x64.v5.0.17", "@dotnet.runtime_packs//microsoft.netcore.app.runtime.linux-x64.v5.0.17"], target_framework = "net5.0", runtime_identifier = "linux-x64")
    runtime_pack(name = "web_net5.0_linux-arm64", packs = ["@dotnet.runtime_packs//microsoft.aspnetcore.app.runtime.linux-arm64.v5.0.17", "@dotnet.runtime_packs//microsoft.netcore.app.runtime.linux-arm64.v5.0.17"], target_framework = "net5.0", runtime_identifier = "linux-arm64")
    runtime_pack(name = "web_net5.0_linux-musl-x64", packs = ["@dotnet.runtime_packs//microsoft.aspnetcore.app.runtime.linux-musl-x64.v5.0.17", "@dotnet.runtime_packs//microsoft.netcore.app.runtime.linux-musl-x64.v5.0.17"], target_framework = "net5.0", runtime_identifier = "linux-musl-x64")
    runtime_pack(name = "web_net5.0_linux-musl-arm64", packs = ["@dotnet.runtime_packs//microsoft.aspnetcore.app.runtime.linux-musl-arm64.v5.0.17", "@dotnet.runtime_packs//microsoft.netcore.app.runtime.linux-musl-arm64.v5.0.17"], target_framework = "net5.0", runtime_identifier = "linux-musl-arm64")
    runtime_pack(name = "web_net5.0_osx-x64", packs = ["@dotnet.runtime_packs//microsoft.aspnetcore.app.runtime.osx-x64.v5.0.17", "@dotnet.runtime_packs//microsoft.netcore.app.runtime.osx-x64.v5.0.17"], target_framework = "net5.0", runtime_identifier = "osx-x64")
    runtime_pack(name = "web_net5.0_win-x64", packs = ["@dotnet.runtime_packs//microsoft.aspnetcore.app.runtime.win-x64.v5.0.17", "@dotnet.runtime_packs//microsoft.netcore.app.runtime.win-x64.v5.0.17"], target_framework = "net5.0", runtime_identifier = "win-x64")
    runtime_pack(name = "web_net5.0_win-arm64", packs = ["@dotnet.runtime_packs//microsoft.aspnetcore.app.runtime.win-arm64.v5.0.17", "@dotnet.runtime_packs//microsoft.netcore.app.runtime.win-arm64.v5.0.17"], target_framework = "net5.0", runtime_identifier = "win-arm64")
    runtime_pack(name = "web_net6.0_linux-x64", packs = ["@dotnet.runtime_packs//microsoft.aspnetcore.app.runtime.linux-x64.v6.0.36", "@dotnet.runtime_packs//microsoft.netcore.app.runtime.linux-x64.v6.0.36"], target_framework = "net6.0", runtime_identifier = "linux-x64")
    runtime_pack(name = "web_net6.0_linux-arm64", packs = ["@dotnet.runtime_packs//microsoft.aspnetcore.app.runtime.linux-arm64.v6.0.36", "@dotnet.runtime_packs//microsoft.netcore.app.runtime.linux-arm64.v6.0.36"], target_framework = "net6.0", runtime_identifier = "linux-arm64")
    runtime_pack(name = "web_net6.0_linux-musl-x64", packs = ["@dotnet.runtime_packs//microsoft.aspnetcore.app.runtime.linux-musl-x64.v6.0.36", "@dotnet.runtime_packs//microsoft.netcore.app.runtime.linux-musl-x64.v6.0.36"], target_framework = "net6.0", runtime_identifier = "linux-musl-x64")
    runtime_pack(name = "web_net6.0_linux-musl-arm64", packs = ["@dotnet.runtime_packs//microsoft.aspnetcore.app.runtime.linux-musl-arm64.v6.0.36", "@dotnet.runtime_packs//microsoft.netcore.app.runtime.linux-musl-arm64.v6.0.36"], target_framework = "net6.0", runtime_identifier = "linux-musl-arm64")
    runtime_pack(name = "web_net6.0_osx-x64", packs = ["@dotnet.runtime_packs//microsoft.aspnetcore.app.runtime.osx-x64.v6.0.36", "@dotnet.runtime_packs//microsoft.netcore.app.runtime.osx-x64.v6.0.36"], target_framework = "net6.0", runtime_identifier = "osx-x64")
    runtime_pack(name = "web_net6.0_osx-arm64", packs = ["@dotnet.runtime_packs//microsoft.aspnetcore.app.runtime.osx-arm64.v6.0.36", "@dotnet.runtime_packs//microsoft.netcore.app.runtime.osx-arm64.v6.0.36"], target_framework = "net6.0", runtime_identifier = "osx-arm64")
    runtime_pack(name = "web_net6.0_win-x64", packs = ["@dotnet.runtime_packs//microsoft.aspnetcore.app.runtime.win-x64.v6.0.36", "@dotnet.runtime_packs//microsoft.netcore.app.runtime.win-x64.v6.0.36"], target_framework = "net6.0", runtime_identifier = "win-x64")
    runtime_pack(name = "web_net6.0_win-arm64", packs = ["@dotnet.runtime_packs//microsoft.aspnetcore.app.runtime.win-arm64.v6.0.36", "@dotnet.runtime_packs//microsoft.netcore.app.runtime.win-arm64.v6.0.36"], target_framework = "net6.0", runtime_identifier = "win-arm64")
    runtime_pack(name = "web_net7.0_linux-x64", packs = ["@dotnet.runtime_packs//microsoft.aspnetcore.app.runtime.linux-x64.v7.0.20", "@dotnet.runtime_packs//microsoft.netcore.app.runtime.linux-x64.v7.0.20"], target_framework = "net7.0", runtime_identifier = "linux-x64")
    runtime_pack(name = "web_net7.0_linux-arm64", packs = ["@dotnet.runtime_packs//microsoft.aspnetcore.app.runtime.linux-arm64.v7.0.20", "@dotnet.runtime_packs//microsoft.netcore.app.runtime.linux-arm64.v7.0.20"], target_framework = "net7.0", runtime_identifier = "linux-arm64")
    runtime_pack(name = "web_net7.0_linux-musl-x64", packs = ["@dotnet.runtime_packs//microsoft.aspnetcore.app.runtime.linux-musl-x64.v7.0.20", "@dotnet.runtime_packs//microsoft.netcore.app.runtime.linux-musl-x64.v7.0.20"], target_framework = "net7.0", runtime_identifier = "linux-musl-x64")
    runtime_pack(name = "web_net7.0_linux-musl-arm64", packs = ["@dotnet.runtime_packs//microsoft.aspnetcore.app.runtime.linux-musl-arm64.v7.0.20", "@dotnet.runtime_packs//microsoft.netcore.app.runtime.linux-musl-arm64.v7.0.20"], target_framework = "net7.0", runtime_identifier = "linux-musl-arm64")
    runtime_pack(name = "web_net7.0_osx-x64", packs = ["@dotnet.runtime_packs//microsoft.aspnetcore.app.runtime.osx-x64.v7.0.20", "@dotnet.runtime_packs//microsoft.netcore.app.runtime.osx-x64.v7.0.20"], target_framework = "net7.0", runtime_identifier = "osx-x64")
    runtime_pack(name = "web_net7.0_osx-arm64", packs = ["@dotnet.runtime_packs//microsoft.aspnetcore.app.runtime.osx-arm64.v7.0.20", "@dotnet.runtime_packs//microsoft.netcore.app.runtime.osx-arm64.v7.0.20"], target_framework = "net7.0", runtime_identifier = "osx-arm64")
    runtime_pack(name = "web_net7.0_win-x64", packs = ["@dotnet.runtime_packs//microsoft.aspnetcore.app.runtime.win-x64.v7.0.20", "@dotnet.runtime_packs//microsoft.netcore.app.runtime.win-x64.v7.0.20"], target_framework = "net7.0", runtime_identifier = "win-x64")
    runtime_pack(name = "web_net7.0_win-arm64", packs = ["@dotnet.runtime_packs//microsoft.aspnetcore.app.runtime.win-arm64.v7.0.20", "@dotnet.runtime_packs//microsoft.netcore.app.runtime.win-arm64.v7.0.20"], target_framework = "net7.0", runtime_identifier = "win-arm64")
    runtime_pack(name = "web_net8.0_linux-x64", packs = ["@dotnet.runtime_packs//microsoft.aspnetcore.app.runtime.linux-x64.v8.0.14", "@dotnet.runtime_packs//microsoft.netcore.app.runtime.linux-x64.v8.0.14"], target_framework = "net8.0", runtime_identifier = "linux-x64")
    runtime_pack(name = "web_net8.0_linux-arm64", packs = ["@dotnet.runtime_packs//microsoft.aspnetcore.app.runtime.linux-arm64.v8.0.14", "@dotnet.runtime_packs//microsoft.netcore.app.runtime.linux-arm64.v8.0.14"], target_framework = "net8.0", runtime_identifier = "linux-arm64")
    runtime_pack(name = "web_net8.0_linux-musl-x64", packs = ["@dotnet.runtime_packs//microsoft.aspnetcore.app.runtime.linux-musl-x64.v8.0.14", "@dotnet.runtime_packs//microsoft.netcore.app.runtime.linux-musl-x64.v8.0.14"], target_framework = "net8.0", runtime_identifier = "linux-musl-x64")
    runtime_pack(name = "web_net8.0_linux-musl-arm64", packs = ["@dotnet.runtime_packs//microsoft.aspnetcore.app.runtime.linux-musl-arm64.v8.0.14", "@dotnet.runtime_packs//microsoft.netcore.app.runtime.linux-musl-arm64.v8.0.14"], target_framework = "net8.0", runtime_identifier = "linux-musl-arm64")
    runtime_pack(name = "web_net8.0_osx-x64", packs = ["@dotnet.runtime_packs//microsoft.aspnetcore.app.runtime.osx-x64.v8.0.14", "@dotnet.runtime_packs//microsoft.netcore.app.runtime.osx-x64.v8.0.14"], target_framework = "net8.0", runtime_identifier = "osx-x64")
    runtime_pack(name = "web_net8.0_osx-arm64", packs = ["@dotnet.runtime_packs//microsoft.aspnetcore.app.runtime.osx-arm64.v8.0.14", "@dotnet.runtime_packs//microsoft.netcore.app.runtime.osx-arm64.v8.0.14"], target_framework = "net8.0", runtime_identifier = "osx-arm64")
    runtime_pack(name = "web_net8.0_win-x64", packs = ["@dotnet.runtime_packs//microsoft.aspnetcore.app.runtime.win-x64.v8.0.14", "@dotnet.runtime_packs//microsoft.netcore.app.runtime.win-x64.v8.0.14"], target_framework = "net8.0", runtime_identifier = "win-x64")
    runtime_pack(name = "web_net8.0_win-arm64", packs = ["@dotnet.runtime_packs//microsoft.aspnetcore.app.runtime.win-arm64.v8.0.14", "@dotnet.runtime_packs//microsoft.netcore.app.runtime.win-arm64.v8.0.14"], target_framework = "net8.0", runtime_identifier = "win-arm64")
    runtime_pack(name = "web_net9.0_linux-x64", packs = ["@dotnet.runtime_packs//microsoft.aspnetcore.app.runtime.linux-x64.v9.0.3", "@dotnet.runtime_packs//microsoft.netcore.app.runtime.linux-x64.v9.0.3"], target_framework = "net9.0", runtime_identifier = "linux-x64")
    runtime_pack(name = "web_net9.0_linux-arm64", packs = ["@dotnet.runtime_packs//microsoft.aspnetcore.app.runtime.linux-arm64.v9.0.3", "@dotnet.runtime_packs//microsoft.netcore.app.runtime.linux-arm64.v9.0.3"], target_framework = "net9.0", runtime_identifier = "linux-arm64")
    runtime_pack(name = "web_net9.0_linux-musl-x64", packs = ["@dotnet.runtime_packs//microsoft.aspnetcore.app.runtime.linux-musl-x64.v9.0.3", "@dotnet.runtime_packs//microsoft.netcore.app.runtime.linux-musl-x64.v9.0.3"], target_framework = "net9.0", runtime_identifier = "linux-musl-x64")
    runtime_pack(name = "web_net9.0_linux-musl-arm64", packs = ["@dotnet.runtime_packs//microsoft.aspnetcore.app.runtime.linux-musl-arm64.v9.0.3", "@dotnet.runtime_packs//microsoft.netcore.app.runtime.linux-musl-arm64.v9.0.3"], target_framework = "net9.0", runtime_identifier = "linux-musl-arm64")
    runtime_pack(name = "web_net9.0_osx-x64", packs = ["@dotnet.runtime_packs//microsoft.aspnetcore.app.runtime.osx-x64.v9.0.3", "@dotnet.runtime_packs//microsoft.netcore.app.runtime.osx-x64.v9.0.3"], target_framework = "net9.0", runtime_identifier = "osx-x64")
    runtime_pack(name = "web_net9.0_osx-arm64", packs = ["@dotnet.runtime_packs//microsoft.aspnetcore.app.runtime.osx-arm64.v9.0.3", "@dotnet.runtime_packs//microsoft.netcore.app.runtime.osx-arm64.v9.0.3"], target_framework = "net9.0", runtime_identifier = "osx-arm64")
    runtime_pack(name = "web_net9.0_win-x64", packs = ["@dotnet.runtime_packs//microsoft.aspnetcore.app.runtime.win-x64.v9.0.3", "@dotnet.runtime_packs//microsoft.netcore.app.runtime.win-x64.v9.0.3"], target_framework = "net9.0", runtime_identifier = "win-x64")
    runtime_pack(name = "web_net9.0_win-arm64", packs = ["@dotnet.runtime_packs//microsoft.aspnetcore.app.runtime.win-arm64.v9.0.3", "@dotnet.runtime_packs//microsoft.netcore.app.runtime.win-arm64.v9.0.3"], target_framework = "net9.0", runtime_identifier = "win-arm64")
