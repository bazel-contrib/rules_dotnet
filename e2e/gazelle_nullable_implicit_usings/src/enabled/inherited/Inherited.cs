namespace Inherited;

public static class Values
{
    public static IReadOnlyList<int> All() => new List<int> { 4, 5 };

    public static Task<int> SumAsync() => Task.FromResult(9);
}
