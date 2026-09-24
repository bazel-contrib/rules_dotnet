namespace RulesDotnet.Tests.NuGetPack
{
    /// <summary>Has no version of its own.</summary>
    public static class Bundled
    {
        /// <summary>Wraps the text in brackets.</summary>
        public static string Decorate(string text) => Deeper.Bracket(text);
    }
}
