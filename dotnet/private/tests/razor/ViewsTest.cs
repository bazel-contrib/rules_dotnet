using System;
using System.Linq;
using System.Reflection;

// MVC discovers compiled views through an assembly attribute that MSBuild
// generates, so an assembly carrying `.cshtml` has to get one too. Nothing in
// the generated code references it, which is exactly why it needs a test.
public static class Program
{
    private const string Factory =
        "Microsoft.AspNetCore.Mvc.ApplicationParts.ProvideApplicationPartFactoryAttribute";

    public static int Main()
    {
        var assembly = Assembly.Load("razor_views");
        var failures = 0;

        var attributes = assembly.GetCustomAttributesData()
            .Select(attribute => attribute.AttributeType.FullName)
            .ToArray();

        if (!attributes.Contains(Factory))
        {
            Console.Error.WriteLine(
                $"razor_views carries no {Factory}, only:\n  " + string.Join("\n  ", attributes));
            failures++;
        }

        // The attribute is worth nothing if the view did not compile alongside
        // it, so check the generated page is there as well.
        var views = assembly.GetTypes().Where(type => type.Name.Contains("Index")).ToArray();
        if (views.Length == 0)
        {
            Console.Error.WriteLine(
                "Views/Index.cshtml generated no type, only:\n  " +
                string.Join("\n  ", assembly.GetTypes().Select(type => type.FullName)));
            failures++;
        }
        else
        {
            Console.WriteLine($"{views[0].FullName} compiled with the application part factory");
        }

        return failures;
    }
}
