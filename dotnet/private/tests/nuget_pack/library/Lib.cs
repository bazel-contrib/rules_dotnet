using System;

namespace RulesDotnet.Tests.NuGetPack
{
    /// <summary>The library that gets packed.</summary>
    public static class Lib
    {
        /// <summary>Greets, using the other assemblies so that they are real dependencies.</summary>
        public static string Greet(string name)
        {
            var span = new ReadOnlySpan<char>(name.ToCharArray());
            return Bundled.Decorate(Mapped.Prefix + Referenced.Shout(span.ToString()));
        }
    }
}
