namespace Lib

module Library =
#if NET11_0 && NET11_0_OR_GREATER && NET10_0_OR_GREATER && NET && NETCOREAPP
    let framework = "net11.0"
#else
    let framework = "missing .NET 11 defines"
#endif

#if NET12_0_OR_GREATER || NETSTANDARD2_0_OR_GREATER || NETFRAMEWORK
    let unexpectedDefines = true
#else
    let unexpectedDefines = false
#endif

    let dependencyFramework = Compat.Library.Framework
    let internal nonPublicMethod () = 42
