using System;
using System.Collections.Generic;
using Newtonsoft.Json;

var message = JsonConvert.DeserializeObject<Dictionary<string, string>>("{\"message\":\"Hello from packages.lock.json\"}");
Console.WriteLine(message["message"]);
