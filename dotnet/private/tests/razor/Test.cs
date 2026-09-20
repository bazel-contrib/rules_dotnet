using System;

// Razor names a component after its path relative to the package, so two
// sources that differ only by directory have to land in different namespaces.
public static class Test
{
    public static int Main()
    {
        var failures = 0;

        failures += Check("Razor.Tests.Widget");
        failures += Check("Razor.Tests.Pages.Widget");

        if (Type.GetType("Razor.Tests.Pages.Widget, razor_components")?.GetProperty("Label") is null)
        {
            Console.Error.WriteLine("Razor.Tests.Pages.Widget.Label was not generated");
            failures++;
        }

        return failures;
    }

    private static int Check(string typeName)
    {
        if (Type.GetType(typeName + ", razor_components") is null)
        {
            Console.Error.WriteLine($"{typeName} was not generated");
            return 1;
        }

        Console.WriteLine($"{typeName} ok");
        return 0;
    }
}
