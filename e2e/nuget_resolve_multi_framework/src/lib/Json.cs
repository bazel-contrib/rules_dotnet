using Newtonsoft.Json;

namespace MultiFramework;

public static class Json
{
    public static string Hello() => JsonConvert.SerializeObject(new { hello = "world" });
}
