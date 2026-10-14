using System;
using Newtonsoft.Json;

var example = JsonConvert.DeserializeObject<Example>(
    "{\"name\":\"Newtonsoft.Json\",\"message\":\"Loaded from packages.lock.json\"}");

if (example == null)
{
    throw new InvalidOperationException("The hardcoded JSON did not deserialize.");
}

Console.WriteLine(example.Message);

public sealed class Example
{
    public string Name { get; set; } = "";
    public string Message { get; set; } = "";
}
