using System;

// With no `root_namespace`, the target name is the root namespace. A target
// name is allowed characters a C# namespace is not, so what a `@using`
// elsewhere has to name is the sanitized form rather than the target name
// itself.
public static class Program
{
    public static int Main()
    {
        const string typeName = "razor_default_namespace.Widget, razor-default-namespace";

        if (Type.GetType(typeName) is null)
        {
            Console.Error.WriteLine($"{typeName} was not generated");
            return 1;
        }

        Console.WriteLine($"{typeName} ok");
        return 0;
    }
}
