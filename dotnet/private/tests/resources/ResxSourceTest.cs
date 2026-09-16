namespace ResxSource.Runtime;

public static class Program
{
    public static int Main()
    {
        var resourceKey = Strings.Hello;
        return Strings.GetResourceString(resourceKey) == "Hello from resx" ? 0 : 1;
    }
}