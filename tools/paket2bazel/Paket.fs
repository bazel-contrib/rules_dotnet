module Paket2Bazel.Paket

open Paket
open System.Collections.Generic
open Paket2Bazel.Models
open System.IO
open System.Security.Cryptography
open Paket.Requirements
open NuGet.Packaging
open NuGet.Frameworks
open NuGet.Versioning
open System
open System.Xml

// List of the supportd TFMS in rules_dotnet
// Needs to be updated when a new TFM is released
let tfms =
    [ "netstandard"
      "netstandard1.0"
      "netstandard1.1"
      "netstandard1.2"
      "netstandard1.3"
      "netstandard1.4"
      "netstandard1.5"
      "netstandard1.6"
      "netstandard2.0"
      "netstandard2.1"
      "net11"
      "net20"
      "net30"
      "net35"
      "net40"
      "net403"
      "net45"
      "net451"
      "net452"
      "net46"
      "net461"
      "net462"
      "net47"
      "net471"
      "net472"
      "net48"
      "netcoreapp1.0"
      "netcoreapp1.1"
      "netcoreapp2.0"
      "netcoreapp2.1"
      "netcoreapp2.2"
      "netcoreapp3.0"
      "netcoreapp3.1"
      "net5.0"
      "net6.0"
      "net7.0"
      "net8.0"
      "net9.0"
      "net10.0" ]
    |> Seq.map (fun f -> NuGetFramework.Parse(f))

let getPackageFilePath (packageName: string) (packageVersion: string) =
    Paket.NuGetCache.GetTargetUserNupkg (Domain.PackageName packageName) (Paket.SemVer.Parse packageVersion)

let getPackageFolderPath (packageName: string) (packageVersion: string) =
    Paket.NuGetCache.GetTargetUserFolder (Domain.PackageName packageName) (Paket.SemVer.Parse packageVersion)

let getClosestFrameworkFiles (targetFramework: NuGetFramework) (frameworkItems: FrameworkSpecificGroup seq) =
    let frameworkReducer = FrameworkReducer()

    let nearest =
        frameworkReducer.GetNearest(targetFramework, (frameworkItems |> Seq.map (fun i -> i.TargetFramework)))

    let frameworkFileItems =
        frameworkItems
        |> Seq.filter (fun i -> i.TargetFramework = nearest)
        |> Seq.collect (fun group -> group.Items)

    frameworkFileItems

let frameworkRestrictionsToTFMs (frameworkRestrictions: FrameworkRestrictions) : FrameworkIdentifier seq =
    match frameworkRestrictions with
    | Paket.Requirements.ExplicitRestriction restriction ->
        restriction.RepresentedFrameworks
        |> Seq.map (fun r -> r.Frameworks)
        |> Seq.concat
    | Paket.Requirements.AutoDetectFramework ->
        failwith
            "Framework auto detection is not supported by paket2bazel. Please specify framework restrictions in the paket.dependencies file."

let getSha512Sri (packageName: string) (packageVersion: string) =
    let path = getPackageFilePath packageName packageVersion

    use stream = File.OpenRead(path)

    use sha512Hash = SHA512.Create()
    let base64 = Convert.ToBase64String(sha512Hash.ComputeHash(stream))

    $"sha512-{base64}"


let getDependenciesPerTFM (tfms: NuGetFramework seq) (allDeps: string seq) (packageReader: PackageFolderReader) =
    let frameworkReducer = FrameworkReducer()
    let deps = packageReader.GetPackageDependencies()

    tfms
    |> Seq.map (fun targetFramework ->
        let nearest =
            frameworkReducer.GetNearest(targetFramework, (deps |> Seq.map (fun i -> i.TargetFramework)))

        let frameworkdeps =
            deps

            |> Seq.filter (fun i -> i.TargetFramework = nearest)
            |> Seq.collect (fun group -> group.Packages)
            // Only use deps that Paket has resolved
            // Paket does not resolve framework built in dependencies
            |> Seq.filter (fun i -> Seq.contains i.Id allDeps)
            |> Seq.map (fun i -> i.Id)

        (targetFramework.GetShortFolderName(), frameworkdeps))
    |> Map.ofSeq

let getOverrides (packageName: string) (packageVersion: string) (packageReader: PackageFolderReader) =
    packageReader.GetItems "data"
    |> Seq.collect (fun f -> f.Items)
    |> Seq.tryFind (fun f -> f.EndsWith("PackageOverrides.txt"))
    |> Option.map (fun f ->
        let path = Path.Combine((getPackageFolderPath packageName packageVersion), f)
        let lines = File.ReadAllLines(path)

        lines |> Array.filter (fun l -> not (String.IsNullOrEmpty l)))
    |> Option.defaultValue [||]

let getFrameworkList (packageName: string) (packageVersion: string) (packageReader: PackageFolderReader) =
    packageReader.GetItems "data"
    |> Seq.collect (fun f -> f.Items)
    |> Seq.tryFind (fun f -> f.EndsWith("FrameworkList.xml"))
    |> Option.map (fun f ->
        let path = Path.Combine((getPackageFolderPath packageName packageVersion), f)
        let xmlDocument = XmlDocument()
        xmlDocument.Load(path)
        let root = xmlDocument.DocumentElement

        root.ChildNodes
        |> Seq.cast<XmlNode>
        |> Seq.filter (fun node -> node.Attributes.ItemOf("Type").Value = "Managed")
        |> Seq.map (fun node ->
            let name = node.Attributes.ItemOf("AssemblyName").Value
            let version = node.Attributes.ItemOf("AssemblyVersion").Value
            $"{name}|{version}")
        |> Seq.filter (fun l -> not (String.IsNullOrEmpty l)))
    |> Option.defaultValue [||]

// https://github.com/dotnet/sdk/blob/main/documentation/general/tool-nuget-package-format.md
let getTools (packageName: string) (packageVersion: string) (packageReader: PackageFolderReader) =
    use nuspec = packageReader.GetNuspec()
    let xmlDocument = XmlDocument()
    xmlDocument.Load(nuspec)
    let root = xmlDocument.DocumentElement

    let isDotnetToolPackage =
        root.ChildNodes
        |> Seq.cast<XmlNode>
        |> Seq.tryFind (fun node -> node.Name = "metadata")
        |> Option.map (fun metadataNode ->
            metadataNode.ChildNodes
            |> Seq.cast<XmlNode>
            |> Seq.tryFind (fun node -> node.Name = "packageTypes")
            |> Option.map (fun packageTypesNode ->
                packageTypesNode.ChildNodes
                |> Seq.cast<XmlNode>
                |> Seq.tryFind (fun node ->
                    node.Name = "packageType" && node.Attributes.ItemOf("name").Value = "DotnetTool")
                |> Option.isSome)
            |> Option.defaultValue false)
        |> Option.defaultValue false

    if isDotnetToolPackage then
        packageReader.GetItems "tools"
        // Some tool packages include a helper executable inside the tools folder, but we don't care about those
        |> Seq.filter (fun fsg -> fsg.TargetFramework <> NuGetFramework.AnyFramework)
        |> Seq.map (fun fsg ->
            let dotnetToolSettingsFile =
                fsg.Items
                |> Seq.tryFind (fun f -> f.EndsWith("DotnetToolSettings.xml"))
                |> Option.defaultWith (fun () -> failwith "DotnetToolSettings.xml not found in tool package")

            let path =
                Path.Combine((getPackageFolderPath packageName packageVersion), dotnetToolSettingsFile)

            let xmlDocument = XmlDocument()
            xmlDocument.Load(path)

            let root = xmlDocument.DocumentElement

            if root.Attributes.ItemOf("Version").Value <> "1" then
                failwith "Unsupported DotnetToolSettings.xml version (expected version 1)"

            let commands = root.FirstChild

            if commands.Name <> "Commands" then
                failwith "Invalid DotnetToolSettings.xml format"

            let tools =
                commands.ChildNodes
                |> Seq.cast<XmlNode>
                |> Seq.filter (fun node -> node.Name = "Command")
                |> Seq.map (fun node ->
                    { name = node.Attributes.ItemOf("Name").Value
                      entrypoint = node.Attributes.ItemOf("EntryPoint").Value
                      runner = node.Attributes.ItemOf("Runner").Value })

            (fsg.TargetFramework.GetShortFolderName(), tools))
        |> Map.ofSeq
    else
        Map.empty

let getDependencies dependenciesFile (cache: Dictionary<string, Package>) =
    let maybeDeps = Dependencies.TryLocate(dependenciesFile)

    match maybeDeps with
    | Some(deps) ->
        deps.SimplePackagesRestore()

        let groups =
            deps.GetInstalledPackages()
            |> Seq.groupBy (fun (group, name, version) -> group)
            |> Seq.map (fun (group, packages) ->

                let sources =
                    deps.GetDependenciesFile().Groups.Item(Domain.GroupName group).Sources
                    |> Seq.map (fun s -> s.Url)

                let packagesInGroup =
                    packages
                    |> Seq.map (fun (_, name, version) ->
                        let found, value = cache.TryGetValue(sprintf "%s-%s" group name)


                        match found with
                        | true -> value
                        | false ->
                            let packageReader = new PackageFolderReader(getPackageFolderPath name version)
                            let sha256 = getSha512Sri name version

                            let package =
                                { name = name
                                  group = group
                                  sha512sri = sha256
                                  sources = sources
                                  version = NuGetVersion.Parse(version).ToFullString()
                                  dependencies =
                                    getDependenciesPerTFM
                                        tfms
                                        (packages |> Seq.map (fun (_, name, _) -> name))
                                        packageReader
                                  overrides = getOverrides name version packageReader
                                  frameworkList = getFrameworkList name version packageReader
                                  tools = getTools name version packageReader }

                            cache.Add((sprintf "%s-%s" group name), package) |> ignore

                            package)

                { name = group
                  packages = packagesInGroup
                  tfms = tfms |> Seq.map (fun f -> f.GetShortFolderName()) })

        groups
    | None -> failwith "Failed to locate paket.dependencies file"
