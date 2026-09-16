namespace TargetingPackNugetConflict
{
    using System;
    using System.Text.Json;

    class Program
    {
        static void Main(string[] args)
        {
            var outputFile = args[0];
            if (string.IsNullOrEmpty(outputFile))
            {
                throw new ArgumentException("Output file path must be provided as the first argument.");
            }
            // We use the System.Text.Json dll for the test. The version of the user provided
            // System.Text.Json is 8.0.5 while the targeting pack has the latest version.
            // We publish a self-contained app targeting:
            // * net9.0 (higher than user provided version),
            // * net8.0 (Same as user provided version),
            // * net7.0 (lower than user provided version).
            // We write the version of the System.Text.Json assembly to the output file in args[0]
            var systemTextJsonAssembly = typeof(System.Text.Json.JsonSerializer).Assembly;
            using (var writer = new System.IO.StreamWriter(outputFile))
            {
                writer.WriteLine($"{systemTextJsonAssembly.GetName().Version}");
            }
        }
    }
}
