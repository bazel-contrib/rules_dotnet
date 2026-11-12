# internals_visible_to

`collect_compile_info` hands the compiler a dependency's internals-carrying
reference assembly when the target being compiled is named in that dependency's
`internals_visible_to`. Under
`--@rules_dotnet//dotnet/settings:strict_deps=false` the same loop also walks
each dependency's transitive closure, so the assembly name it matches on has to
survive that walk. CI runs the suite with strict deps both on and off.

`consumer` depends on `chain` and then `secrets`. `chain` has a dependency of
its own, so the closure walk runs before `secrets` is reached; `secrets` is the
one that grants its internals to `consumer`. If the name is lost during the
walk, the compile fails with CS0117.

That order is also the one buildifier sorts `deps` into, so formatting the file
cannot quietly defeat the test. Renaming either library would.

`outsider` is not named in `internals_visible_to`, so it compiles against the
reference assembly a second, `/refonly` compile of `secrets` produces; nothing
builds that compile otherwise. `secrets` is compiled with `code_block_analyzer`,
a diagnostic analyzer built against Roslyn's NuGet packages. Were those packages
handed to the compiler as analyzers beside it, Roslyn's own compiler diagnostic
analyzer would run too and crash the `/refonly` compile.

`transitive_consumer` reaches `secrets` only through `relay`, the way a project
does through MSBuild's transitive ProjectReferences. With strict deps off it has
to be handed the internals-carrying reference assembly of `secrets` out of that
closure, or it fails with CS0117. With strict deps on it cannot see `secrets` at
all, as with MSBuild's `DisableTransitiveProjectReferences`, so it is only built
with them off.

`fsharp_consumer` reaches `fsharp_secrets` directly and, with strict deps off,
through `fsharp_relay` as well. The public reference assembly of `fsharp_secrets`
must not be handed over beside the internals-carrying one: given both, fsc
compiles against the public one and fails with FS0491. csc keeps whichever of
two assemblies with the same identity comes last, so a C# twin would not catch
this. `fsharp_transitive_consumer` is the F# twin of `transitive_consumer`.
