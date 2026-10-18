using Newtonsoft.Json;

public static class Program
{
    public static void Main()
    {
        System.Console.WriteLine(JsonConvert.SerializeObject(new { hello = "world" }));
    }
}
