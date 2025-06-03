# Targeting pack confligt with NuGet package

This test checks that DLLs provided by a targeting pack that conflict with DLLs in a user provided by a NuGet package
are resolved correctly. The rules are:

* If the targeting pack version is higher or equal to the NuGet package version, the targeting pack DLL is used.
* If the NuGet package version is higher than the targeting pack version, the NuGet package DLL is used.

We also need to make sure that the behaviour is the same in both a the `csharp_binary/fsharp_binary` rules and the `publish_binary`.
