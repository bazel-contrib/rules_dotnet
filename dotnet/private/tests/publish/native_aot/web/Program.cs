using System;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Net.Http.Json;
using System.Runtime.CompilerServices;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Hosting.Server;
using Microsoft.AspNetCore.Hosting.Server.Features;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;

// An ASP.NET Core minimal API in the shape of the `webapiaot` template: a slim
// builder, source generated JSON and request delegates. It serves itself on a
// loopback port and calls its own endpoints, so running the NativeAOT image
// proves the whole web stack survived trimming and ahead-of-time compilation.
public static class Program
{
    private static int _failures;

    public static async Task<int> Main(string[] args)
    {
        var builder = WebApplication.CreateSlimBuilder(args);
        builder.WebHost.UseUrls("http://127.0.0.1:0");
        builder.Logging.ClearProviders();
        builder.Services.ConfigureHttpJsonOptions(options =>
            options.SerializerOptions.TypeInfoResolverChain.Insert(0, AppJsonContext.Default));

        var app = builder.Build();
        var todos = new[] { new Todo(1, "Walk the dog", false), new Todo(2, "Do the dishes", true) };
        var api = app.MapGroup("/todos");
        api.MapGet("/", () => todos);
        api.MapGet("/{id}", (int id) =>
            todos.FirstOrDefault(t => t.Id == id) is { } todo ? Results.Ok(todo) : Results.NotFound());
        api.MapPost("/", (Todo todo) => Results.Created($"/todos/{todo.Id}", todo));

        await app.StartAsync();
        var address = app.Services.GetRequiredService<IServer>().Features
            .Get<IServerAddressesFeature>()!.Addresses.First();

        using (var client = new HttpClient { BaseAddress = new Uri(address) })
        {
            var all = await client.GetFromJsonAsync("todos", AppJsonContext.Default.TodoArray);
            Expect(all is { Length: 2 } && all[0].Title == "Walk the dog", "lists todos");

            var one = await client.GetFromJsonAsync("todos/2", AppJsonContext.Default.Todo);
            Expect(one is { Id: 2, IsComplete: true }, "binds a route parameter");

            using var missing = await client.GetAsync("todos/3");
            Expect(missing.StatusCode == HttpStatusCode.NotFound, $"missing todo: {missing.StatusCode}");

            using var created = await client.PostAsJsonAsync("todos", new Todo(3, "Ship it", false), AppJsonContext.Default.Todo);
            Expect(created.StatusCode == HttpStatusCode.Created, $"binds a JSON body: {created.StatusCode}");
            Expect(created.Headers.Location?.ToString() == "/todos/3", $"location: {created.Headers.Location}");
        }

        await app.StopAsync();

        Expect(!RuntimeFeature.IsDynamicCodeSupported, "runs as NativeAOT, without a JIT");
        Console.WriteLine(_failures == 0 ? "the NativeAOT web service works" : "FAILED");
        return _failures;
    }

    private static void Expect(bool condition, string description)
    {
        Console.WriteLine((condition ? "ok: " : "FAILED: ") + description);
        if (!condition) _failures++;
    }
}

public record Todo(int Id, string Title, bool IsComplete);

// Web defaults, camelCase as the server writes, so the client can read it.
[JsonSourceGenerationOptions(JsonSerializerDefaults.Web)]
[JsonSerializable(typeof(Todo))]
[JsonSerializable(typeof(Todo[]))]
internal partial class AppJsonContext : JsonSerializerContext
{
}
