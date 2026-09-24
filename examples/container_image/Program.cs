using System;
using System.Linq;
using Mono.Cecil;

namespace Hello
{
    public static class Program
    {
        public static void Main()
        {
            Console.WriteLine(Greeting.Greeter.Greet("container"));

            // Mono.Cecil, from NuGet, reads the application's own assembly.
            using var module = ModuleDefinition.ReadModule(typeof(Program).Assembly.Location);
            Console.WriteLine($"{module.Name} defines {module.Types.Count(type => type.Name != "<Module>")} type(s).");
        }
    }
}
