public static class GenericTest
{
    public static int Main()
    {
        var values = new List<int> { 1, 2 };
        return values.Count == 2 ? 0 : 1;
    }
}
