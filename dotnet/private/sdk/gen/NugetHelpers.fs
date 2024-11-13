[<RequireQualifiedAccess>]
module NugetHelpers

open NuGet.Common
open System.Threading
open NuGet.Protocol.Core.Types
open NuGet.Configuration
open System
open System.Collections.Generic
open Paket
open Paket.PackageResolver
open NuGet.Frameworks
open NuGet.Packaging
open Paket.Requirements
open System.IO
open System.Security.Cryptography
open System.Xml
open System.Collections.Concurrent
open NuGet.Versioning

type private NuGetLogger() =
    interface ILogger with
        member this.LogDebug(message) = printf "%s" message
        member this.LogVerbose(message) = printfn "%s" message
        member this.LogInformation(message) = printfn "%s" message
        member this.LogMinimal(message) = printfn "%s" message
        member this.LogWarning(message) = printfn "%s" message
        member this.LogError(message) = printfn "%s" message
        member this.Log(level: LogLevel, message: string) : unit = printfn "%s" message
        member this.Log(message: ILogMessage) : unit = printfn "%s" message.Message
        member this.LogAsync(level: LogLevel, message: string) : Tasks.Task = task { printfn "%s" message }
        member this.LogAsync(message: ILogMessage) : Tasks.Task = task { printfn "%s" message.Message }
        member this.LogInformationSummary(message: string) : unit = printfn "%s" message

type Package =
    { id: string
      version: string
      sha512sri: string
      sources: string seq
      dependencies: Map<string, seq<Package>>
      overrides: string seq
      frameworkList: string seq }


let private logger = NuGetLogger()
let packageCache = ConcurrentDictionary<string, Package>()

let nugetV3Feed = "https://api.nuget.org/v3/index.json"

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
      "net9.0" ]
    |> Seq.map (fun f -> NuGetFramework.Parse(f))

let getAllVersions packageId =
    let providers = new List<Lazy<INuGetResourceProvider>>()
    providers.AddRange(Repository.Provider.GetCoreV3()) // Add v3 API support
    let packageSource = new PackageSource("https://api.nuget.org/v3/index.json")
    let sourceRepository = new SourceRepository(packageSource, providers)
    let cache = new SourceCacheContext()

    let packageSearchResource = sourceRepository.GetResource<FindPackageByIdResource>()


    let result =
        packageSearchResource.GetAllVersionsAsync(packageId, cache, logger, CancellationToken.None)

    result.Result |> Seq.map (fun v -> v) |> Seq.toList

let downloadPackage packageId version =
    Paket.NuGet.DownloadAndExtractPackage(
        None,
        "",
        false,
        PackagesFolderGroupConfig.NoPackagesFolder,
        PackageSources.PackageSource.NuGetV3Source "https://api.nuget.org/v3/index.json",
        [],
        Domain.GroupName "wat",
        Domain.PackageName packageId,
        SemVer.Parse version,
        ResolvedPackageKind.Package,
        false,
        false,
        false,
        true
    )

let private getPackageFilePath (packageName: string) (packageVersion: string) =
    Paket.NuGetCache.GetTargetUserNupkg (Domain.PackageName packageName) (Paket.SemVer.Parse packageVersion)

let private getPackageFolderPath (packageName: string) (packageVersion: string) =
    Paket.NuGetCache.GetTargetUserFolder (Domain.PackageName packageName) (Paket.SemVer.Parse packageVersion)

let private getClosestFrameworkFiles (targetFramework: NuGetFramework) (frameworkItems: FrameworkSpecificGroup seq) =
    let frameworkReducer = FrameworkReducer()

    let nearest =
        frameworkReducer.GetNearest(targetFramework, (frameworkItems |> Seq.map (fun i -> i.TargetFramework)))

    let frameworkFileItems =
        frameworkItems
        |> Seq.filter (fun i -> i.TargetFramework = nearest)
        |> Seq.collect (fun group -> group.Items)

    frameworkFileItems

let private frameworkRestrictionsToTFMs (frameworkRestrictions: FrameworkRestrictions) : FrameworkIdentifier seq =
    match frameworkRestrictions with
    | Paket.Requirements.ExplicitRestriction restriction ->
        restriction.RepresentedFrameworks
        |> Seq.map (fun r -> r.Frameworks)
        |> Seq.concat
    | Paket.Requirements.AutoDetectFramework ->
        failwith
            "Framework auto detection is not supported by paket2bazel. Please specify framework restrictions in the paket.dependencies file."

let private getSha512Sri (packageName: string) (packageVersion: string) =
    let path = getPackageFilePath packageName packageVersion

    use stream = File.OpenRead(path)

    use sha512Hash = SHA512.Create()
    let base64 = Convert.ToBase64String(sha512Hash.ComputeHash(stream))

    $"sha512-{base64}"


let private getDependenciesPerTFM (tfms: NuGetFramework seq) (packageReader: PackageFolderReader) =
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
            |> Seq.map (fun i -> (i.Id, i.VersionRange.MinVersion.ToFullString()))

        (targetFramework.GetShortFolderName(), frameworkdeps))
    |> Map.ofSeq

let private getOverrides (packageName: string) (packageVersion: string) (packageReader: PackageFolderReader) =
    packageReader.GetItems "data"
    |> Seq.collect (fun f -> f.Items)
    |> Seq.tryFind (fun f -> f.EndsWith("PackageOverrides.txt"))
    |> Option.map (fun f ->
        let path = Path.Combine((getPackageFolderPath packageName packageVersion), f)
        let lines = File.ReadAllLines(path)

        lines |> Array.filter (fun l -> not (String.IsNullOrEmpty l)))
    |> Option.defaultValue [||]

let private getFrameworkList (packageName: string) (packageVersion: string) (packageReader: PackageFolderReader) =
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
        |> Seq.filter (fun node ->
            node.Attributes.ItemOf("Type") <> null
            && node.Attributes.ItemOf("Type").Value = "Managed")
        |> Seq.map (fun node ->
            let name = node.Attributes.ItemOf("AssemblyName").Value
            let version = node.Attributes.ItemOf("AssemblyVersion").Value
            $"{name}|{version}")
        |> Seq.filter (fun l -> not (String.IsNullOrEmpty l)))
    |> Option.defaultValue [||]

let rec getPackageInfo id version source =
    let found, value = packageCache.TryGetValue(sprintf "%s-%s" id version)

    match found with
    | true -> value
    | false ->
        downloadPackage id version |> Async.RunSynchronously |> ignore
        let packageReader = new PackageFolderReader(getPackageFolderPath id version)
        let sha512sri = getSha512Sri id version

        let dependencies =
            getDependenciesPerTFM tfms packageReader
            |> Map.map (fun tfm deps -> deps |> Seq.map (fun (id, version) -> getPackageInfo id version source))

        let package =
            { id = id
              sha512sri = sha512sri
              sources = [ source ]
              version = NuGetVersion.Parse(version).ToFullString()
              dependencies = dependencies
              overrides = getOverrides id version packageReader
              frameworkList = getFrameworkList id version packageReader }

        packageCache.TryAdd((sprintf "%s-%s" id version), package) |> ignore

        package
