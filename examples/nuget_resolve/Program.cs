using Serilog;

public static class Program
{
    public static void Main()
    {
        Log.Logger = new LoggerConfiguration()
            .MinimumLevel.Debug()
            .WriteTo.Console()
            .CreateLogger();
        Log.Information("Hello from {Example}", "nuget_resolve");
        Log.CloseAndFlush();
    }
}
