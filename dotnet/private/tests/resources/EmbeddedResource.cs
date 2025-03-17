using System.Linq;

public static class Program
{
    private static void AssertEqual<T>(T expected, T actual)
    {
        if (!expected.Equals(actual))
        {
            throw new System.Exception($"Expected {expected} but got {actual}");
        }
    }

    private static void AssertContains<T>(
        System.Collections.Generic.IEnumerable<T> haystack,
        T needle
    )
    {
        if (!haystack.Contains(needle))
        {
            throw new System.Exception(
                $"Expected {needle} to be in [{string.Join(", ", haystack.Select(x => x.ToString()))}]"
            );
        }
    }

    public static void Main()
    {
        var assembly = System.Reflection.Assembly.GetExecutingAssembly();
        var resources = assembly.GetManifestResourceNames();
        AssertContains(resources, "EmbeddedResource.Library.nested.path.to.resource.txt");

        using var stream = assembly.GetManifestResourceStream(
            "EmbeddedResource.Library.nested.path.to.resource.txt"
        );
        using var reader = new System.IO.StreamReader(stream);
        var content = reader.ReadToEnd();
        AssertEqual("Well hello friends! :^)", content.Trim());
    }
}
