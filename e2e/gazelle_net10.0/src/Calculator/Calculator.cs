using Newtonsoft.Json;

namespace Calculator;

public static class Arithmetic
{
    public static int Add(int a, int b) => a + b;

    public static string ResultToJson(int value) => JsonConvert.SerializeObject(new { result = value });
}
