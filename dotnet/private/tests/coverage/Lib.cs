using System.Collections.Generic;

namespace Coverage;

public static class Lib
{
    public static int Covered(int x)
    {
        if (x > 0)
        {
            return x + 1;
        }

        return Uncovered();
    }

    public static int Uncovered() => -1;

    // A generic signature: its LCOV method name carries commas.
    public static int Count<TKey, TValue>(Dictionary<TKey, TValue> values)
        where TKey : notnull => values.Count;
}
