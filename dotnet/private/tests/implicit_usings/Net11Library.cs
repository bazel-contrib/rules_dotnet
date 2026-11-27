namespace ImplicitUsingsNet11Lib;

public static class Net11Library
{
    public static Task<string?> GetAsync(HttpClient client) =>
        client.GetFromJsonAsync<string>("https://example.invalid/");
}
