"GENERATED"

load("@rules_dotnet//dotnet:defs.bzl", "nuget_repo")

def rules_dotnet_nuget_tool_tests():
    "rules_dotnet_nuget_tool_tests"
    nuget_repo(
        name = "paket.rules_dotnet_nuget_tool_tests",
        packages = [
            {"name": "CSharpier", "id": "CSharpier", "version": "1.0.3", "sha512": "sha512-Kx2qiVF5nXJG/nbEWNQxle30B+xyH/R59jMxS47p8JTvcPm0zq727PvWFEa2buPZfKZ3gq2UVTWW1wk0LQXKog==", "sources": ["https://api.nuget.org/v3/index.json"], "dependencies": {"net11": [], "net20": [], "net30": [], "net35": [], "net40": [], "net403": [], "net45": [], "net451": [], "net452": [], "net46": [], "net461": [], "net462": [], "net47": [], "net471": [], "net472": [], "net48": [], "net5.0": [], "net6.0": [], "net7.0": [], "net8.0": [], "net9.0": [], "netcoreapp1.0": [], "netcoreapp1.1": [], "netcoreapp2.0": [], "netcoreapp2.1": [], "netcoreapp2.2": [], "netcoreapp3.0": [], "netcoreapp3.1": [], "netstandard": [], "netstandard1.0": [], "netstandard1.1": [], "netstandard1.2": [], "netstandard1.3": [], "netstandard1.4": [], "netstandard1.5": [], "netstandard1.6": [], "netstandard2.0": [], "netstandard2.1": []}, "targeting_pack_overrides": [], "framework_list": [], "tools": {"net8.0": [{"name": "csharpier", "entrypoint": "CSharpier.dll", "runner": "dotnet"}], "net9.0": [{"name": "csharpier", "entrypoint": "CSharpier.dll", "runner": "dotnet"}]}},
            {"name": "Paket", "id": "Paket", "version": "9.0.2", "sha512": "sha512-VPMh+F1IvraKlKUJlVjI/nyr5eyKQMNLKbGcFo+pKpcvN2bAnrFl5WafGZ4A/ZTzLl0eyjb3AVcLx8Z/S8DF0g==", "sources": ["https://api.nuget.org/v3/index.json"], "dependencies": {"net11": [], "net20": [], "net30": [], "net35": [], "net40": [], "net403": [], "net45": [], "net451": [], "net452": [], "net46": [], "net461": [], "net462": [], "net47": [], "net471": [], "net472": [], "net48": [], "net5.0": [], "net6.0": [], "net7.0": [], "net8.0": [], "net9.0": [], "netcoreapp1.0": [], "netcoreapp1.1": [], "netcoreapp2.0": [], "netcoreapp2.1": [], "netcoreapp2.2": [], "netcoreapp3.0": [], "netcoreapp3.1": [], "netstandard": [], "netstandard1.0": [], "netstandard1.1": [], "netstandard1.2": [], "netstandard1.3": [], "netstandard1.4": [], "netstandard1.5": [], "netstandard1.6": [], "netstandard2.0": [], "netstandard2.1": []}, "targeting_pack_overrides": [], "framework_list": [], "tools": {"netcoreapp3.1": [{"name": "paket", "entrypoint": "paket.dll", "runner": "dotnet"}]}},
        ],
    )
