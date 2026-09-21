using System;
using Example.Components;
using Example.Components.Pages;

public static class Program
{
    public static int Main()
    {
        var type = typeof(Greeting);

        if (type.Namespace != "Example.Components.Pages")
        {
            Console.Error.WriteLine($"unexpected namespace: {type.Namespace}");
            return 1;
        }

        var parameter = type.GetProperty("Name");
        if (parameter is null)
        {
            Console.Error.WriteLine("Greeting.Name was not generated");
            return 1;
        }

        Console.WriteLine($"{type.FullName} ok, Counter.Next() = {Counter.Next()}");
        return 0;
    }
}
