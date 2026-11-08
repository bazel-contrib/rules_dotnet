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

`aggregator` has no sources of its own and re-exports `exported_secrets`, which
also grants its internals to `consumer`. `collect_compile_info` must forward the
exported assembly's internals-carrying reference assembly (`irefs`) across
`exports` when the consumer is named in its `internals_visible_to`.
