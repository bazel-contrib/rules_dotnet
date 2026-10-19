using Microsoft.Extensions.DependencyInjection;
using Serilog;

public static class Program
{
    public static void Main()
    {
        // ServiceDescriptor lives in Microsoft.Extensions.DependencyInjection.Abstractions,
        // the deepest package of the Http -> Logging -> DependencyInjection -> Abstractions chain.
        ServiceDescriptor descriptor = ServiceDescriptor.Singleton<string>("hello");
        Log.Logger = new LoggerConfiguration().MinimumLevel.Debug().CreateLogger();
        Log.Information("deep chain type: {Type}", descriptor.ServiceType.FullName);
        // Serilog has no sink configured (Sinks.File writes files, Sinks.Async only
        // wraps another sink), so say it on the console too — this line is what
        // the e2e asserts on.
        System.Console.WriteLine("deep chain type: " + descriptor.ServiceType.FullName);
    }
}
