using Microsoft.AspNetCore.Builder;
using Microsoft.Extensions.Configuration;

// Regression test for https://github.com/bazel-contrib/rules_dotnet/issues/467
//
// Calling a configuration binder API such as `.Get<T>()` makes the
// `Microsoft.Extensions.Configuration.Binder.SourceGeneration` source generator emit an
// interceptor. That generator ships both in the ASP.NET Core targeting pack (pulled in by
// `project_sdk = "web"`) and in the `Microsoft.Extensions.Configuration.Binder` NuGet package,
// so before analyzer de-duplication the generator ran twice and the build failed with CS0433
// (duplicate `InterceptsLocationAttribute`).
public class Program
{
    public static void Main(string[] args)
    {
        WebApplicationBuilder builder = WebApplication.CreateBuilder(args);
        MyOptions options = builder.Configuration.GetSection("My").Get<MyOptions>() ?? new MyOptions();
        System.Console.WriteLine(options.Name + options.Count);
    }
}

public class MyOptions
{
    public string Name { get; set; } = "";
    public int Count { get; set; }
}
