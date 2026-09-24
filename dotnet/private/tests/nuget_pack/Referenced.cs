namespace RulesDotnet.Tests.NuGetPack
{
    /// <summary>Versioned, but shipped by no package the tests declare.</summary>
    public static class Referenced
    {
        /// <summary>Upper-cases the text.</summary>
        public static string Shout(string text) => text.ToUpperInvariant();
    }
}
