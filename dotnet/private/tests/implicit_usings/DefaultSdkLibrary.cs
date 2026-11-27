namespace CustomHttp
{
    public sealed class HttpClient
    {
        public string Name => "custom";
    }
}

namespace ImplicitUsingsLib
{
    public static class DefaultSdkLibrary
    {
        public static List<string> Describe(string leaf)
        {
            var client = new HttpClient();
            var combined = Path.Combine("root", leaf).Replace('\\', '/');
            var count = Enumerable.Range(1, 3).Sum();
            var json = JsonSerializer.Serialize(new[] { combined, client.Name, count.ToString() });
            return JsonSerializer.Deserialize<List<string>>(json)!;
        }

        internal static Task<string> InternalGreetingAsync(string name) =>
            Task.FromResult($"Hello, {name}!");
    }
}
