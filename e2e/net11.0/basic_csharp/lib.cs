#if !NET11_0 || !NET11_0_OR_GREATER || !NET10_0_OR_GREATER || !NET || !NETCOREAPP
#error Missing .NET 11 framework defines.
#endif
#if NET12_0_OR_GREATER || NETSTANDARD2_0_OR_GREATER || NETFRAMEWORK
#error Unexpected framework defines.
#endif

namespace Lib
{
    public static class Library
    {
        public const string Framework = "net11.0";
        public static string DependencyFramework => Compat.Library.Framework;
        internal static int NonPublicMethod() => 42;
    }
}
