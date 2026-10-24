namespace ImplicitUsings;

public static class Library
{
    public static IReadOnlyList<int> Values() => new List<int> { 1, 2 };

    public static Task<int> Answer() => Task.FromResult(42);
}
