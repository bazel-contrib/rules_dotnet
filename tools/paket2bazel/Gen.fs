module Paket2Bazel.Gen

open Paket
open FSharpx.Collections
open FSharpx
open System
open System.Text
open Paket2Bazel.Models
open System.IO

let generateTarget (group: Group) =
    let i = "    "
    let sb = new StringBuilder()
    sb.Append($"{i}nuget_repo(\n") |> ignore

    sb.Append($"{i}    name = \"paket.{group.name.ToLower()}\",\n")
    |> ignore

    sb.Append($"{i}    packages = [\n") |> ignore

    for package in group.packages do
        // TODO: Handle multiple TFMS
        let packageDeps =
            package.dependencies
            |> Map.values
            |> Seq.head
            |> Seq.fold (fun state current -> state + $"\"{current}\", ") ""
            |> (fun s ->
                if String.IsNullOrEmpty(s) then
                    s
                else
                    s.Substring(0, s.Length - 2))

        let overrides =
            package.overrides
            |> Seq.fold (fun state current -> state + $"\"{current}\", ") ""
            |> (fun s ->
                if String.IsNullOrEmpty(s) then
                    s
                else
                    s.Substring(0, s.Length - 2))

        sb.Append(
            $"{i}        (\"{package.name}\", \"{package.version}\", \"{package.sha512sri}\", [{packageDeps}], [{overrides}]),\n"
        )
        |> ignore


    sb.Append($"{i}    ],\n") |> ignore
    sb.Append($"{i})\n") |> ignore

    sb.ToString()

let addFileHeaderContent (sb: StringBuilder) (fileName: string) =
    sb.Append($"\"Generated by paket2bazel\"\n")
    |> ignore

    sb.Append($"\n") |> ignore

    sb.Append("load(\"@rules_dotnet//dotnet:defs.bzl\", \"nuget_repo\")")
    |> ignore

    sb.Append("\n") |> ignore
    sb.Append("\n") |> ignore
    sb.Append($"def {fileName}():") |> ignore
    sb.Append("\n") |> ignore
    sb.Append($"    \"{fileName}\"") |> ignore
    sb.Append("\n") |> ignore

let addGroupToFileContent (sb: StringBuilder) (group: Group) =
    sb.Append(generateTarget group) |> ignore

let generateBazelFiles (groups: Group seq) (separateFiles: bool) (outputFolder: string) =
    if separateFiles then
        groups
        |> Seq.iter (fun group ->
            let sb = new StringBuilder()
            addFileHeaderContent sb group.name
            addGroupToFileContent sb group
            File.WriteAllText($"{outputFolder}/{group.name}.bzl", sb.ToString()))
    else
        let sb = new StringBuilder()

        addFileHeaderContent sb "paket"

        groups
        |> Seq.sortBy (fun i -> i.name)
        |> Seq.map (fun g -> generateTarget g)
        |> Seq.iter (fun i -> i |> Seq.iter (fun x -> sb.Append(x) |> ignore))

        File.WriteAllText($"{outputFolder}/paket.bzl", sb.ToString())
