using Microsoft.AspNetCore.Builder;
using Microsoft.Extensions.DependencyInjection;

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddRazorPages();

var app = builder.Build();

// The served tree is laid out next to the binary the way a published
// application expects it, with the endpoint manifest beside the assembly, so
// this needs no further setup under `bazel run`.
app.MapStaticAssets();
app.MapRazorPages().WithStaticAssets();

app.Run("http://localhost:8000");
