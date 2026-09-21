namespace Example.Components;

// Plain C# compiled into the same assembly as the .razor files.
public static class Counter
{
    private static int _value;

    public static int Next() => ++_value;
}
