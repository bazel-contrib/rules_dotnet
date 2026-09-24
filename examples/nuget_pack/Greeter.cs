using System.Collections.Immutable;

namespace Example
{
    /// <summary>Greets people.</summary>
    public static class Greeter
    {
        /// <summary>Greets everyone named, once each.</summary>
        public static string Greet(params string[] names)
        {
            var unique = names.ToImmutableSortedSet();
            return Formatting.Exclaim("Hello, " + string.Join(" and ", unique));
        }
    }
}
