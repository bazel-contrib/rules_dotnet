using Core;

namespace User;

public static class Program
{
    public static void Main()
    {
        // Ensure that the Core library was linked in as a runtime dependency.
        var util = new MyUtility();
        util.Frobnicate();
    }
}
