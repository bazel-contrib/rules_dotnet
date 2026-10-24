namespace Enabled;

public static class Values
{
    public static IReadOnlyList<int> All() => new List<int> { 2, 3 };

    public static Task<int> SumAsync() => Task.FromResult(5);
}
