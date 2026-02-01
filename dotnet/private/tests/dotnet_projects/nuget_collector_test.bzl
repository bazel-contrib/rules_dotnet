"Tests for NuGet collector utilities"

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//dotnet/private/rules/dotnet_projects:nuget_collector.bzl", "create_nuget_collector")

def _basic_collection_test_impl(ctx):
    env = unittest.begin(ctx)

    collector = create_nuget_collector()

    # Add some packages
    collector.add_package("Newtonsoft.Json", "13.0.3", "project1.csproj")
    collector.add_package("Microsoft.Extensions.Logging", "8.0.0", "project2.csproj")

    resolved = collector.resolve_packages()

    asserts.equals(env, 2, len(resolved))

    # Packages should be sorted by id (case-insensitive)
    asserts.equals(env, "Microsoft.Extensions.Logging", resolved[0].id)
    asserts.equals(env, "8.0.0", resolved[0].version)
    asserts.equals(env, "Newtonsoft.Json", resolved[1].id)
    asserts.equals(env, "13.0.3", resolved[1].version)

    return unittest.end(env)

basic_collection_test = unittest.make(_basic_collection_test_impl)

def _version_conflict_resolution_test_impl(ctx):
    env = unittest.begin(ctx)

    collector = create_nuget_collector()

    # Add same package with different versions
    collector.add_package("Newtonsoft.Json", "12.0.0", "project1.csproj")
    collector.add_package("Newtonsoft.Json", "13.0.3", "project2.csproj")
    collector.add_package("Newtonsoft.Json", "13.0.1", "project3.csproj")

    resolved = collector.resolve_packages()

    # Should resolve to highest version
    asserts.equals(env, 1, len(resolved))
    asserts.equals(env, "Newtonsoft.Json", resolved[0].id)
    asserts.equals(env, "13.0.3", resolved[0].version)

    # Should report conflicts
    conflicts = collector.get_version_conflicts()
    asserts.equals(env, 1, len(conflicts))
    asserts.equals(env, "Newtonsoft.Json", conflicts[0].id)
    asserts.true(env, "12.0.0" in conflicts[0].versions)
    asserts.true(env, "13.0.3" in conflicts[0].versions)
    asserts.true(env, "13.0.1" in conflicts[0].versions)

    return unittest.end(env)

version_conflict_resolution_test = unittest.make(_version_conflict_resolution_test_impl)

def _add_packages_from_project_test_impl(ctx):
    env = unittest.begin(ctx)

    collector = create_nuget_collector()

    # Simulate package references from a project
    package_refs = [
        struct(id = "PackageA", version = "1.0.0"),
        struct(id = "PackageB", version = "2.0.0"),
    ]

    collector.add_packages_from_project(package_refs, "test.csproj")

    resolved = collector.resolve_packages()

    asserts.equals(env, 2, len(resolved))
    asserts.equals(env, "PackageA", resolved[0].id)
    asserts.equals(env, "1.0.0", resolved[0].version)
    asserts.equals(env, "PackageB", resolved[1].id)
    asserts.equals(env, "2.0.0", resolved[1].version)

    return unittest.end(env)

add_packages_from_project_test = unittest.make(_add_packages_from_project_test_impl)

def _semver_comparison_test_impl(ctx):
    env = unittest.begin(ctx)

    collector = create_nuget_collector()

    # Test various version formats
    collector.add_package("TestPkg", "1.0.0", "p1.csproj")
    collector.add_package("TestPkg", "1.0.1", "p2.csproj")
    collector.add_package("TestPkg", "1.1.0", "p3.csproj")
    collector.add_package("TestPkg", "2.0.0", "p4.csproj")

    resolved = collector.resolve_packages()

    asserts.equals(env, 1, len(resolved))
    asserts.equals(env, "2.0.0", resolved[0].version)

    return unittest.end(env)

semver_comparison_test = unittest.make(_semver_comparison_test_impl)

def _prerelease_version_test_impl(ctx):
    env = unittest.begin(ctx)

    collector = create_nuget_collector()

    # Prerelease versions should be lower than release
    collector.add_package("TestPkg", "2.0.0-beta.1", "p1.csproj")
    collector.add_package("TestPkg", "2.0.0", "p2.csproj")
    collector.add_package("TestPkg", "2.0.0-alpha", "p3.csproj")

    resolved = collector.resolve_packages()

    asserts.equals(env, 1, len(resolved))
    asserts.equals(env, "2.0.0", resolved[0].version)

    return unittest.end(env)

prerelease_version_test = unittest.make(_prerelease_version_test_impl)

def _empty_version_test_impl(ctx):
    env = unittest.begin(ctx)

    collector = create_nuget_collector()

    # Package with no version specified
    collector.add_package("NoVersionPkg", "", "p1.csproj")

    resolved = collector.resolve_packages()

    asserts.equals(env, 1, len(resolved))
    asserts.equals(env, "NoVersionPkg", resolved[0].id)
    asserts.equals(env, "", resolved[0].version)

    return unittest.end(env)

empty_version_test = unittest.make(_empty_version_test_impl)

def _case_insensitive_id_test_impl(ctx):
    env = unittest.begin(ctx)

    collector = create_nuget_collector()

    # Same package with different casing
    collector.add_package("Newtonsoft.Json", "13.0.3", "p1.csproj")
    collector.add_package("newtonsoft.json", "13.0.2", "p2.csproj")
    collector.add_package("NEWTONSOFT.JSON", "13.0.1", "p3.csproj")

    resolved = collector.resolve_packages()

    # Should be treated as same package
    asserts.equals(env, 1, len(resolved))
    asserts.equals(env, "13.0.3", resolved[0].version)

    return unittest.end(env)

case_insensitive_id_test = unittest.make(_case_insensitive_id_test_impl)

def nuget_collector_test_suite(name):
    unittest.suite(
        name,
        basic_collection_test,
        version_conflict_resolution_test,
        add_packages_from_project_test,
        semver_comparison_test,
        prerelease_version_test,
        empty_version_test,
        case_insensitive_id_test,
    )
