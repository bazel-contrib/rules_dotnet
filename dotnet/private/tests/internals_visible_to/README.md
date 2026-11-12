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

`transitive_consumer` reaches `secrets` only through `relay`, so with strict deps
off it has to be handed the internals-carrying reference assembly of `secrets`
out of the closure, or it fails with CS0117. With strict deps on it cannot see
`secrets` at all, so it is only built with them off.
`fsharp_transitive_consumer` is its F# twin.

A friend must never be handed the public reference assembly beside the
internals-carrying one: of two with the same identity, fsc keeps the first and
csc the last. `fsharp_consumer` reaches `fsharp_secrets` directly and, with
strict deps off, through `fsharp_relay`, which would put the public one first.
`export_consumer` reaches `secrets` through the `exports` of `exporter`, which
would put it last, and with strict deps on would hand over only the public one.
