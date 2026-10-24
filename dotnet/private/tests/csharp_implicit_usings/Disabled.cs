using System.Collections.Generic;

namespace ImplicitUsings;

public static class Disabled
{
    public static int Count() => new List<int> { 1, 2 }.Count;
}
