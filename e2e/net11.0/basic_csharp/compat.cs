#if NET11_0 || NET11_0_OR_GREATER
#error Older targets must not acquire .NET 11 defines.
#endif

namespace Compat
{
    public static class Library
    {
#if NET10_0
        public const string Framework = "net10.0";
#elif NETSTANDARD2_0
        public const string Framework = "netstandard2.0";
#else
#error Unexpected compatibility target.
#endif
    }
}
