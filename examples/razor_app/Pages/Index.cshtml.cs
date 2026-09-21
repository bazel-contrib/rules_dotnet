using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;

namespace Example.RazorApp.Pages;

// The page model is ordinary C#, compiled into the same assembly as the
// `.cshtml` that declares it with `@model`.
public class IndexModel : PageModel
{
    [BindProperty(SupportsGet = true)]
    public string Name { get; set; } = "world";

    public string Greeting => $"Hello, {Name}!";
}
