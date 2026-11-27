namespace ImplicitUsingsWebLib;

public static class WebSdkLibrary
{
    public static void Configure(WebApplication app)
    {
        IConfiguration config = app.Configuration;
        IHostEnvironment env = app.Environment;
        ILogger logger = app.Logger;
        IEndpointRouteBuilder routes = app;
        _ = typeof(HttpClientJsonExtensions);
        _ = typeof(ServiceCollection);
        routes.MapGet("/ping", (HttpContext ctx) => Results.Ok($"{env.EnvironmentName}:{config["Key"]}:{logger != null}:{ctx != null}"));
    }
}
