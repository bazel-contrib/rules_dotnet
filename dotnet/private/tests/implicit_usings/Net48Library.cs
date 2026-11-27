namespace ImplicitUsingsNet48Lib;

public static class Net48Library
{
    public static Task<int> SumWithPathAsync()
    {
        var items = new List<int> { 1, 2, Path.GetFileName("a/b.txt").Length };
        return Task.FromResult(items.Sum());
    }
}
