using System;

namespace RulesDotnet.Tests.NuGetPack
{
    /// <summary>Versioned, but shipped by no package the tests declare.</summary>
    public static class Referenced
    {
        /// <summary>Upper-cases the text, through System.Memory as the library does.</summary>
        public static string Shout(string text) => new ReadOnlySpan<char>(text.ToUpperInvariant().ToCharArray()).ToString();
    }
}
