module Paket2Bazel.Gen

open Paket
open System.Collections.Generic
open NuGet.Packaging
open NuGet.Frameworks
open FSharpx.Option
open FSharpx.Collections
open FSharpx
open System.IO
open System.Security.Cryptography
open System.Text
open Paket2Bazel.Models


let getLibFile (tfms: NuGetFramework list) (packageName: string) (packageReader: PackageFolderReader) =
    let frameworkReducer = FrameworkReducer()
    let allLibItems = packageReader.GetLibItems()

    tfms
    |> List.map
        (fun targetFramework ->
            let nearest =
                frameworkReducer.GetNearest(
                    targetFramework,
                    (allLibItems
                     |> Seq.map (fun i -> i.TargetFramework))
                )

            let libItems =
                allLibItems
                |> Seq.filter (fun i -> i.TargetFramework = nearest)
                |> Seq.collect (fun group -> group.Items)
                |> Seq.filter (fun i -> i.EndsWith(".dll"))

            match libItems
                  |> Seq.tryFind
                      (fun i ->
                          i
                              .ToLower()
                              .Contains($"/{packageName.ToLower()}.dll")) with
            | Some (lib) -> Some((targetFramework.GetShortFolderName(), lib))
            | None ->
                match libItems |> Seq.tryHead with
                | Some (head) -> Some((targetFramework.GetShortFolderName(), head))
                | None -> None)
    |> List.choose id
    |> Map.ofList

let getRefItems (tfms: NuGetFramework list) (packageName: string) (packageReader: PackageFolderReader) =
    let frameworkReducer = FrameworkReducer()
    let allRefItems = packageReader.GetReferenceItems()

    tfms
    |> List.map
        (fun targetFramework ->
            let nearest =
                frameworkReducer.GetNearest(
                    targetFramework,
                    (allRefItems
                     |> Seq.map (fun i -> i.TargetFramework))
                )

            let refItems =
                allRefItems
                |> Seq.filter (fun i -> i.TargetFramework = nearest)
                |> Seq.collect (fun group -> group.Items)
                |> Seq.filter (fun i -> i.EndsWith(".dll"))

            match refItems
                  |> Seq.tryFind
                      (fun i ->
                          i
                              .ToLower()
                              .Contains($"/{packageName.ToLower()}.dll")) with
            | Some (lib) -> Some((targetFramework.GetShortFolderName(), lib))
            | None ->
                match refItems |> Seq.tryHead with
                | Some (head) -> Some((targetFramework.GetShortFolderName(), head))
                | None -> None)
    |> List.choose id
    |> Map.ofList

// TODO: Do something for tools
let getToolItems (tfms: NuGetFramework list) (packageName: string) (packageReader: PackageFolderReader) =
    let frameworkReducer = FrameworkReducer()
    let toolItems = packageReader.GetToolItems()

    tfms
    |> List.map
        (fun targetFramework ->
            let nearest =
                frameworkReducer.GetNearest(targetFramework, (toolItems |> Seq.map (fun i -> i.TargetFramework)))

            let toolItems =
                toolItems
                |> Seq.filter (fun i -> i.TargetFramework = nearest)
                |> Seq.collect (fun group -> group.Items)

            match toolItems
                  |> Seq.tryFind
                      (fun i ->
                          i
                              .ToLower()
                              .Contains($"/{packageName.ToLower()}.dll")) with
            | Some (lib) -> Some((targetFramework.GetShortFolderName(), lib))
            | None ->
                match toolItems |> Seq.tryHead with
                | Some (head) -> Some((targetFramework.GetShortFolderName(), head))
                | None -> None)
    |> List.choose id
    |> Map.ofList

let getItems (tfms: NuGetFramework list) folderName (packageReader: PackageFolderReader) =
    let frameworkReducer = FrameworkReducer()

    let fileItems = packageReader.GetItems(folderName)

    tfms
    |> List.map
        (fun targetFramework ->
            let nearest =
                frameworkReducer.GetNearest(targetFramework, (fileItems |> Seq.map (fun i -> i.TargetFramework)))

            let frameworkFileItems =
                fileItems
                |> Seq.filter (fun i -> i.TargetFramework = nearest)
                |> Seq.collect (fun group -> group.Items)
                |> Seq.toList

            (targetFramework.GetShortFolderName(), frameworkFileItems))

let getFiles (tfms: NuGetFramework list) (packageReader: PackageFolderReader) =
    let frameworkReducer = FrameworkReducer()

    let dict = Dictionary<string, string list>()

    getItems tfms "lib" packageReader
    |> List.append (getItems tfms "runtimes" packageReader)
    |> List.append (getItems tfms "typeproviders" packageReader)
    |> List.append (getItems tfms "tools" packageReader)
    |> List.iter
        (fun (x, y) ->
            if dict.ContainsKey(x) then
                let prev = dict.GetValueOrDefault(x, [])
                dict.Remove(x) |> ignore
                dict.Add(x, prev |> List.append y)
            else
                dict.Add(x, y))


    dict.ToFSharpList()
    |> List.map (fun i -> (i.Key, i.Value))
    |> Map.ofList

let getDependenciesPerFramework (tfms: NuGetFramework list) (allDeps: string list) (group: string) (packageReader: PackageFolderReader) =
    let frameworkReducer = FrameworkReducer()

    let deps = packageReader.GetPackageDependencies()

    tfms
    |> List.map
        (fun targetFramework ->
            let nearest =
                frameworkReducer.GetNearest(targetFramework, (deps |> Seq.map (fun i -> i.TargetFramework)))

            let frameworkdeps =
                deps
                // Only use deps that Paket has resolved
                // Paket does not resolve framework built in dependencies
                |> Seq.filter (fun i -> i.TargetFramework = nearest)
                |> Seq.collect (fun group -> group.Packages)
                |> Seq.filter (fun i -> List.contains i.Id allDeps)
                |> Seq.map (fun i ->
                    $"@{group.ToLower()}.{i.Id.ToLower()}//:lib") 
                |> Seq.toList

            (targetFramework.GetShortFolderName(), frameworkdeps)) |> Map.ofList

let getSha256 (packagesFolderPath: string) (packageName: string) (packageVersion: string) =
    use stream =
        File.OpenRead($"{packagesFolderPath}/{packageName}/{packageName.ToLower()}.{packageVersion}.nupkg")

    use sha256 = SHA256.Create()
    let bytes = sha256.ComputeHash(stream)
    let mutable result = ""

    for b in bytes do
        result <- result + b.ToString("x2")

    result

let processInstalledPackages (groups: Group list) paketDir : ProcessedPackage list =
    groups
    |> List.map
        (fun group ->
            let packages =
                group.packages 
                |> List.map (fun d -> 
                    let tfms = group.tfms |> List.map NuGetFramework.Parse
                    let packageReader =
                        new PackageFolderReader(
                            if group.name.ToLower() = "main" then
                                $"{paketDir}/packages/{d.name}"
                            else
                                $"{paketDir}/packages/{group.name}/{d.name}"
                        )

                    maybe {
                        let sha256 =
                            getSha256
                                (if group.name.ToLower() = "main" then
                                    $"{paketDir}/packages"
                                else
                                    $"{paketDir}/packages/{group.name}")
                                d.name
                                d.version

                        let libFile = getLibFile tfms d.name packageReader
                        let refItems = getRefItems tfms d.name packageReader
                        let toolItems = getToolItems tfms d.name packageReader
                        let fileItems = getFiles tfms packageReader

                        let deps =
                            getDependenciesPerFramework tfms (group.packages |> List.map (fun d -> d.name)) group.name packageReader

                        let targetedPackages =
                            tfms
                            |> Seq.map
                                (fun tfm ->
                                    let tfm = tfm.GetShortFolderName()
                                    let targetedPackage: TargetedPackage =
                                        { lib = Map.tryFind tfm libFile
                                          deps = Map.findOrDefault tfm [] deps
                                          ref = Map.tryFind tfm refItems
                                          tool = Map.tryFind tfm toolItems
                                          pdb = (Map.tryFind tfm fileItems) |>Option.bind (fun files -> List.tryFind (fun x -> x.EndsWith(".pdb")) files)
                                          files = Map.findOrDefault tfm [] fileItems |> List.filter (fun x -> not (x.EndsWith(".pdb"))) }

                                    (tfm, targetedPackage))
                            |> Map.ofSeq

                        return
                            { name = $"{group.name.ToLower()}.{d.name.ToLower()}"
                              package = d.name.ToLower()
                              group = group.name
                              version = d.version
                              buildFileOverride = d.buildFileOverride
                              sha256 = sha256
                              targets = targetedPackages }})
            packages |> List.choose id
        ) |> List.concat

let generateTarget (package: ProcessedPackage) =
    let i = "    "
    let sb = new StringBuilder()
    sb.Append($"{i}nuget_package(\n") |> ignore

    sb.Append($"{i}    name = \"{package.name.ToLower()}\",\n")
    |> ignore

    sb.Append($"{i}    package = \"{package.package.ToLower()}\",\n")
    |> ignore

    sb.Append($"{i}    version = \"{package.version}\",\n")
    |> ignore

    sb.Append($"{i}    sha256 = \"{package.sha256}\",\n")
    |> ignore

    sb.Append($"{i}    build_file_content = \"\"\"\n")
    |> ignore

    sb.Append(
        $"load(\"@rules_dotnet//dotnet:defs.bzl\", \"import_library\", \"import_multiframework_library\")\n"
    )
    |> ignore

    let tfms = package.targets.Keys |> Seq.map NuGetFramework.Parse |> Seq.toList
    for tfm in tfms do
        let tfm =tfm.GetShortFolderName()
        let lib = package.targets |> Map.tryFind (tfm)
        sb.Append($"import_library(\n") |> ignore
        sb.Append($"    name = \"{tfm}\",\n") |> ignore

        sb.Append($"    target_framework = \"{tfm}\",\n")
        |> ignore
        if lib.IsSome then

            if lib.Value.lib.IsSome then
                sb.Append($"    dll = \"{lib.Value.lib.Value}\",\n")
                |> ignore

            if lib.Value.ref.IsSome then 
                sb.Append($"    refdll = \"{lib.Value.ref.Value}\",\n")
                |> ignore

            if lib.Value.pdb.IsSome then 
                sb.Append($"    pdb = \"{lib.Value.pdb.Value}\",\n")
                |> ignore

            sb.Append($"    deps = [\n") |> ignore
            for dep in lib.Value.deps do
                sb.Append($"        \"{dep}\",\n") |> ignore
            sb.Append($"    ],\n") |> ignore

            sb.Append($"    data = [\n") |> ignore
            for file in lib.Value.files do
                sb.Append($"        \"{file}\",\n") |> ignore
            sb.Append($"    ],\n") |> ignore
            sb.Append($")\n") |> ignore

    sb.Append($"import_multiframework_library(\n") |> ignore
    sb.Append($"    name = \"lib\",\n") |> ignore
    for tfm in tfms do
        let attrName =tfm.GetShortFolderName().Replace(".", "_") 
        sb.Append($"    {attrName} = \":{tfm.GetShortFolderName()}\",\n") |> ignore
    sb.Append($"    visibility = [\"//visibility:public\"],\n") |> ignore
    
    sb.Append($")\n") |> ignore
    
    sb.Append($"\"\"\",\n") |> ignore

    sb.Append($"{i})\n") |> ignore
    sb.ToString()

let generateTargetWithOverride (buildFile: string) package =
    let i = "    "
    let sb = new StringBuilder()
    sb.Append($"{i}nuget_package(\n") |> ignore

    sb.Append($"{i}    name = \"{package.name.ToLower()}\",\n")
    |> ignore

    sb.Append($"{i}    package = \"{package.package.ToLower()}\",\n")
    |> ignore

    sb.Append($"{i}    version = \"{package.version}\",\n")
    |> ignore

    sb.Append($"{i}    sha256 = \"{package.sha256}\",\n")
    |> ignore

    sb.Append($"{i}    build_file = \"{buildFile}\",\n")
    |> ignore

    sb.Append($"{i})\n") |> ignore

    sb.ToString()

let generateBazelFile (packages: ProcessedPackage list) =
    let sb = new StringBuilder()

    sb.Append($"\"Generated by paket2bazel\"\n") |> ignore
    sb.Append($"\n") |> ignore
    sb.Append("load(\"@rules_dotnet//dotnet:defs.bzl\", \"nuget_package\")")
    |> ignore

    sb.Append("\n") |> ignore
    sb.Append("\n") |> ignore
    sb.Append("def paket():") |> ignore
    sb.Append("\n") |> ignore
    sb.Append("    \"paket\"") |> ignore
    sb.Append("\n") |> ignore

    packages
    |> List.sortBy (fun i -> i.name)
    |> List.map
        (fun i ->
            match i.buildFileOverride with
            | Some (buildFile) -> generateTargetWithOverride buildFile i
            | None -> generateTarget i)
    |> List.iter (fun i -> sb.Append(i) |> ignore)

    sb.ToString()
