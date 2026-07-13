using System;

namespace Localization
{
    public static class Program
    {
        public static void Main()
        {
            // The neutral resource is embedded in the assembly; the French and German
            // translations are resolved from the satellite assemblies that rules_dotnet
            // builds next to it (fr/Localization.resources.dll, de/Localization.resources.dll).
            foreach (var culture in new[] { "", "fr", "de" })
            {
                var label = string.IsNullOrEmpty(culture) ? "neutral" : culture;
                Console.WriteLine($"{label}: {Greeter.Hello(culture)}");
            }
        }
    }
}
