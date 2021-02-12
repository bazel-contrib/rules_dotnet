"Template file"

load("@io_bazel_rules_dotnet//dotnet:defs.bzl", "nuget_package")

def project_dotnet_repositories_nuget():
    " Nuget declarations "

    ### Generated by the tool
    nuget_package(
        name = "system.buffers",
        package = "system.buffers",
        version = "4.4.0",
        sha256 = "293c408586b0146d95e555f58f0de9cf1dc8ad05d1827d53b2f8233e0c406ea0",
    )
    nuget_package(
        name = "system.numerics.vectors",
        package = "system.numerics.vectors",
        version = "4.4.0",
        sha256 = "6ae5d02b67e52ff2699c1feb11c01c526e2f60c09830432258e0809486aabb65",
    )
    nuget_package(
        name = "system.runtime.compilerservices.unsafe",
        package = "system.runtime.compilerservices.unsafe",
        version = "4.5.2",
        sha256 = "f1e5175c658ed8b2fbb804cc6727b6882a503844e7da309c8d4846e9ca11e4ef",
        core_lib = {
            "netcoreapp2.0": "lib/netcoreapp2.0/System.Runtime.CompilerServices.Unsafe.dll",
            "netcoreapp2.1": "lib/netcoreapp2.0/System.Runtime.CompilerServices.Unsafe.dll",
            "netcoreapp3.0": "lib/netcoreapp2.0/System.Runtime.CompilerServices.Unsafe.dll",
            "netcoreapp3.1": "lib/netcoreapp2.0/System.Runtime.CompilerServices.Unsafe.dll",
        },
        core_ref = {
            "netcoreapp2.0": "ref/netstandard2.0/System.Runtime.CompilerServices.Unsafe.dll",
            "netcoreapp2.1": "ref/netstandard2.0/System.Runtime.CompilerServices.Unsafe.dll",
            "netcoreapp3.0": "ref/netstandard2.0/System.Runtime.CompilerServices.Unsafe.dll",
            "netcoreapp3.1": "ref/netstandard2.0/System.Runtime.CompilerServices.Unsafe.dll",
        },
        core_files = {
            "netcoreapp2.0": [
                "lib/netcoreapp2.0/System.Runtime.CompilerServices.Unsafe.dll",
                "lib/netcoreapp2.0/System.Runtime.CompilerServices.Unsafe.xml",
            ],
            "netcoreapp2.1": [
                "lib/netcoreapp2.0/System.Runtime.CompilerServices.Unsafe.dll",
                "lib/netcoreapp2.0/System.Runtime.CompilerServices.Unsafe.xml",
            ],
            "netcoreapp3.0": [
                "lib/netcoreapp2.0/System.Runtime.CompilerServices.Unsafe.dll",
                "lib/netcoreapp2.0/System.Runtime.CompilerServices.Unsafe.xml",
            ],
            "netcoreapp3.1": [
                "lib/netcoreapp2.0/System.Runtime.CompilerServices.Unsafe.dll",
                "lib/netcoreapp2.0/System.Runtime.CompilerServices.Unsafe.xml",
            ],
        },
    )
    nuget_package(
        name = "system.memory",
        package = "system.memory",
        version = "4.5.3",
        sha256 = "0af97b45b45b46ef6a2b37910568dabd492c793da3859054595d523e2a545859",
        core_lib = {
            "netcoreapp2.0": "lib/netstandard2.0/System.Memory.dll",
        },
        core_deps = {
            "netcoreapp2.0": [
                "@system.runtime.compilerservices.unsafe//:netcoreapp2.0_core",
            ],
        },
        core_files = {
            "netcoreapp2.0": [
                "lib/netstandard2.0/System.Memory.dll",
                "lib/netstandard2.0/System.Memory.xml",
            ],
        },
    )
    nuget_package(
        name = "grpc.core.api",
        package = "grpc.core.api",
        version = "2.28.1",
        sha256 = "f4abd6db983c1e8d99d53830aeb86b5ac6a9b2298295f496eec9451073d47760",
        core_lib = {
            "netcoreapp2.0": "lib/netstandard2.0/Grpc.Core.Api.dll",
            "netcoreapp2.1": "lib/netstandard2.0/Grpc.Core.Api.dll",
            "netcoreapp3.0": "lib/netstandard2.0/Grpc.Core.Api.dll",
            "netcoreapp3.1": "lib/netstandard2.0/Grpc.Core.Api.dll",
        },
        core_deps = {
            "netcoreapp2.0": [
                "@system.memory//:netcoreapp2.0_core",
            ],
            "netcoreapp2.1": [
                "@system.memory//:netcoreapp2.1_core",
            ],
            "netcoreapp3.0": [
                "@system.memory//:netcoreapp3.0_core",
            ],
            "netcoreapp3.1": [
                "@system.memory//:netcoreapp3.1_core",
            ],
        },
        core_files = {
            "netcoreapp2.0": [
                "lib/netstandard2.0/Grpc.Core.Api.dll",
                "lib/netstandard2.0/Grpc.Core.Api.pdb",
                "lib/netstandard2.0/Grpc.Core.Api.xml",
            ],
            "netcoreapp2.1": [
                "lib/netstandard2.0/Grpc.Core.Api.dll",
                "lib/netstandard2.0/Grpc.Core.Api.pdb",
                "lib/netstandard2.0/Grpc.Core.Api.xml",
            ],
            "netcoreapp3.0": [
                "lib/netstandard2.0/Grpc.Core.Api.dll",
                "lib/netstandard2.0/Grpc.Core.Api.pdb",
                "lib/netstandard2.0/Grpc.Core.Api.xml",
            ],
            "netcoreapp3.1": [
                "lib/netstandard2.0/Grpc.Core.Api.dll",
                "lib/netstandard2.0/Grpc.Core.Api.pdb",
                "lib/netstandard2.0/Grpc.Core.Api.xml",
            ],
        },
    )
    nuget_package(
        name = "grpc.core",
        package = "grpc.core",
        version = "2.28.1",
        sha256 = "b625817b7e8dfe66e0894b232001b4c2f0e80aa41dc4dccb59d5a452ca36a755",
        core_lib = {
            "netcoreapp2.0": "lib/netstandard2.0/Grpc.Core.dll",
            "netcoreapp2.1": "lib/netstandard2.0/Grpc.Core.dll",
            "netcoreapp3.0": "lib/netstandard2.0/Grpc.Core.dll",
            "netcoreapp3.1": "lib/netstandard2.0/Grpc.Core.dll",
        },
        core_deps = {
            "netcoreapp2.0": [
                "@grpc.core.api//:netcoreapp2.0_core",
                "@system.memory//:netcoreapp2.0_core",
            ],
            "netcoreapp2.1": [
                "@grpc.core.api//:netcoreapp2.1_core",
                "@system.memory//:netcoreapp2.1_core",
            ],
            "netcoreapp3.0": [
                "@grpc.core.api//:netcoreapp3.0_core",
                "@system.memory//:netcoreapp3.0_core",
            ],
            "netcoreapp3.1": [
                "@grpc.core.api//:netcoreapp3.1_core",
                "@system.memory//:netcoreapp3.1_core",
            ],
        },
        core_files = {
            "netcoreapp2.0": [
                "lib/netstandard2.0/Grpc.Core.dll",
                "lib/netstandard2.0/Grpc.Core.pdb",
                "lib/netstandard2.0/Grpc.Core.xml",
            ],
            "netcoreapp2.1": [
                "lib/netstandard2.0/Grpc.Core.dll",
                "lib/netstandard2.0/Grpc.Core.pdb",
                "lib/netstandard2.0/Grpc.Core.xml",
            ],
            "netcoreapp3.0": [
                "lib/netstandard2.0/Grpc.Core.dll",
                "lib/netstandard2.0/Grpc.Core.pdb",
                "lib/netstandard2.0/Grpc.Core.xml",
            ],
            "netcoreapp3.1": [
                "lib/netstandard2.0/Grpc.Core.dll",
                "lib/netstandard2.0/Grpc.Core.pdb",
                "lib/netstandard2.0/Grpc.Core.xml",
            ],
        },
    )
    nuget_package(
        name = "system.threading.tasks.extensions",
        package = "system.threading.tasks.extensions",
        version = "4.5.2",
        sha256 = "12a245f53a693074cabe947a7a6add03ad736a5316dc7c2b67b8fa067e1b06ea",
        core_lib = {
            "netcoreapp2.0": "lib/netstandard2.0/System.Threading.Tasks.Extensions.dll",
        },
        core_deps = {
            "netcoreapp2.0": [
                "@system.runtime.compilerservices.unsafe//:netcoreapp2.0_core",
            ],
        },
        core_files = {
            "netcoreapp2.0": [
                "lib/netstandard2.0/System.Threading.Tasks.Extensions.dll",
                "lib/netstandard2.0/System.Threading.Tasks.Extensions.xml",
            ],
        },
    )
    nuget_package(
        name = "system.threading.channels",
        package = "system.threading.channels",
        version = "4.6.0",
        sha256 = "42d6eb4a5023bb237e5d19e715d67ce99e1e0ccea186e247bb5aa222eacb795a",
        core_lib = {
            "netcoreapp2.0": "lib/netstandard2.0/System.Threading.Channels.dll",
            "netcoreapp2.1": "lib/netstandard2.0/System.Threading.Channels.dll",
            "netcoreapp3.0": "lib/netcoreapp3.0/System.Threading.Channels.dll",
            "netcoreapp3.1": "lib/netcoreapp3.0/System.Threading.Channels.dll",
        },
        core_deps = {
            "netcoreapp2.0": [
                "@system.threading.tasks.extensions//:netcoreapp2.0_core",
            ],
        },
        core_files = {
            "netcoreapp2.0": [
                "lib/netstandard2.0/System.Threading.Channels.dll",
                "lib/netstandard2.0/System.Threading.Channels.xml",
            ],
            "netcoreapp2.1": [
                "lib/netstandard2.0/System.Threading.Channels.dll",
                "lib/netstandard2.0/System.Threading.Channels.xml",
            ],
            "netcoreapp3.0": [
                "lib/netcoreapp3.0/System.Threading.Channels.dll",
                "lib/netcoreapp3.0/System.Threading.Channels.xml",
            ],
            "netcoreapp3.1": [
                "lib/netcoreapp3.0/System.Threading.Channels.dll",
                "lib/netcoreapp3.0/System.Threading.Channels.xml",
            ],
        },
    )
    nuget_package(
        name = "grpc.healthcheck",
        package = "grpc.healthcheck",
        version = "2.28.1",
        sha256 = "7e1761d5e0f2339e6805cfd7d345bff53f4ae61a7a951a19d5ed9b065fa91065",
        core_lib = {
            "netcoreapp2.0": "lib/netstandard2.0/Grpc.HealthCheck.dll",
            "netcoreapp2.1": "lib/netstandard2.0/Grpc.HealthCheck.dll",
            "netcoreapp3.0": "lib/netstandard2.0/Grpc.HealthCheck.dll",
            "netcoreapp3.1": "lib/netstandard2.0/Grpc.HealthCheck.dll",
        },
        core_deps = {
            "netcoreapp2.0": [
                "@grpc.core.api//:netcoreapp2.0_core",
                "@google.protobuf//:netcoreapp2.0_core",
                "@system.threading.channels//:netcoreapp2.0_core",
            ],
            "netcoreapp2.1": [
                "@grpc.core.api//:netcoreapp2.1_core",
                "@google.protobuf//:netcoreapp2.1_core",
                "@system.threading.channels//:netcoreapp2.1_core",
            ],
            "netcoreapp3.0": [
                "@grpc.core.api//:netcoreapp3.0_core",
                "@google.protobuf//:netcoreapp3.0_core",
                "@system.threading.channels//:netcoreapp3.0_core",
            ],
            "netcoreapp3.1": [
                "@grpc.core.api//:netcoreapp3.1_core",
                "@google.protobuf//:netcoreapp3.1_core",
                "@system.threading.channels//:netcoreapp3.1_core",
            ],
        },
        core_files = {
            "netcoreapp2.0": [
                "lib/netstandard2.0/Grpc.HealthCheck.dll",
                "lib/netstandard2.0/Grpc.HealthCheck.pdb",
                "lib/netstandard2.0/Grpc.HealthCheck.xml",
            ],
            "netcoreapp2.1": [
                "lib/netstandard2.0/Grpc.HealthCheck.dll",
                "lib/netstandard2.0/Grpc.HealthCheck.pdb",
                "lib/netstandard2.0/Grpc.HealthCheck.xml",
            ],
            "netcoreapp3.0": [
                "lib/netstandard2.0/Grpc.HealthCheck.dll",
                "lib/netstandard2.0/Grpc.HealthCheck.pdb",
                "lib/netstandard2.0/Grpc.HealthCheck.xml",
            ],
            "netcoreapp3.1": [
                "lib/netstandard2.0/Grpc.HealthCheck.dll",
                "lib/netstandard2.0/Grpc.HealthCheck.pdb",
                "lib/netstandard2.0/Grpc.HealthCheck.xml",
            ],
        },
    )
    nuget_package(
        name = "google.protobuf",
        package = "google.protobuf",
        version = "3.12.0-rc1",
        sha256 = "d4c138dd7152d48940c3af6c9d81b619e4fd865a23b6786a1877314d9f6cc26d",
        core_lib = {
            "netcoreapp2.0": "lib/netstandard2.0/Google.Protobuf.dll",
            "netcoreapp2.1": "lib/netstandard2.0/Google.Protobuf.dll",
            "netcoreapp3.0": "lib/netstandard2.0/Google.Protobuf.dll",
            "netcoreapp3.1": "lib/netstandard2.0/Google.Protobuf.dll",
        },
        core_deps = {
            "netcoreapp2.0": [
                "@system.memory//:netcoreapp2.0_core",
            ],
            "netcoreapp2.1": [
                "@system.memory//:netcoreapp2.1_core",
            ],
            "netcoreapp3.0": [
                "@system.memory//:netcoreapp3.0_core",
            ],
            "netcoreapp3.1": [
                "@system.memory//:netcoreapp3.1_core",
            ],
        },
        core_files = {
            "netcoreapp2.0": [
                "lib/netstandard2.0/Google.Protobuf.dll",
                "lib/netstandard2.0/Google.Protobuf.pdb",
                "lib/netstandard2.0/Google.Protobuf.xml",
            ],
            "netcoreapp2.1": [
                "lib/netstandard2.0/Google.Protobuf.dll",
                "lib/netstandard2.0/Google.Protobuf.pdb",
                "lib/netstandard2.0/Google.Protobuf.xml",
            ],
            "netcoreapp3.0": [
                "lib/netstandard2.0/Google.Protobuf.dll",
                "lib/netstandard2.0/Google.Protobuf.pdb",
                "lib/netstandard2.0/Google.Protobuf.xml",
            ],
            "netcoreapp3.1": [
                "lib/netstandard2.0/Google.Protobuf.dll",
                "lib/netstandard2.0/Google.Protobuf.pdb",
                "lib/netstandard2.0/Google.Protobuf.xml",
            ],
        },
    )

    ### End of generated by the tool
    return
