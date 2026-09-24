namespace RulesDotnet.Tests.NuGetPack
{
    /// <summary>Reached only through <c>Bundled</c>.</summary>
    public static class Deeper
    {
        /// <summary>Wraps the text in brackets.</summary>
        public static string Bracket(string text) => "[" + text + "]";
    }
}
