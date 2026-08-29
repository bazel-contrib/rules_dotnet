module Paket2Bazel.Models

open System.Collections.Generic

type DotnetTool =
    { name: string
      entrypoint: string
      runner: string }

type Package =
    { name: string
      group: string
      version: string
      sha512sri: string
      sources: string seq
      dependencies: Map<string, seq<string>>
      overrides: string seq
      frameworkList: string seq
      tools: Map<string, seq<DotnetTool>> }

type Group =
    { name: string
      packages: Package seq
      tfms: string seq }
