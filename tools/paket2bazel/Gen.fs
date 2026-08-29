module Paket2Bazel.Gen

open System.Text
open Paket2Bazel.Models
open System.IO
open System.Collections.Generic

let generateBazelFiles (groups: Group seq) (outputFolder: string) (netrcLabel: string option) =
    groups
    |> Seq.iter (fun group ->

        let packages: NugetRepo.NugetRepoPackage seq =
            group.packages
            |> Seq.map (fun p ->
                { name = p.name
                  id = p.name
                  version = p.version
                  sha512 = p.sha512sri
                  sources = p.sources
                  netrc = netrcLabel
                  dependencies = Dictionary(p.dependencies)
                  targeting_pack_overrides = p.overrides
                  framework_list = p.frameworkList
                  tools =
                      p.tools
                      |> Map.map (fun _ ts ->
                          ts
                          |> Seq.map (fun t ->
                              { NugetRepo.NugetRepoTool.name = t.name
                                NugetRepo.NugetRepoTool.entrypoint = t.entrypoint
                                NugetRepo.NugetRepoTool.runner = t.runner }))
                      |> Dictionary })

        NugetRepo.generateBazelFiles $"{group.name.ToLower()}" packages outputFolder "paket.")
