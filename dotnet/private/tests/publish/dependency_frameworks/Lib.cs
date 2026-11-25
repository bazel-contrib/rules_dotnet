namespace DependencyFrameworks
{
    public static class Lib
    {
        // Loads an assembly of Microsoft.AspNetCore.App.
        public static string Name() => typeof(Microsoft.AspNetCore.Http.HttpContext).Assembly.GetName().Name!;
    }
}
