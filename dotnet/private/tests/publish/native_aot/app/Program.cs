using System;
using System.Linq;

namespace AotApp
{
    public static class Program
    {
        public static void Main()
        {
            // Enough managed work that the output cannot be an empty shell:
            // generics, LINQ and string formatting all have to survive ilc.
            var squares = Enumerable.Range(1, 5).Select(n => n * n).ToArray();
            Console.WriteLine("Hello from NativeAOT: {0}", string.Join(",", squares));
        }
    }
}
