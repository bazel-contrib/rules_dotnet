using Newtonsoft.Json;

namespace Store;

public static class Serializer
{
    public static string ToJson(object value) => JsonConvert.SerializeObject(value);
}
