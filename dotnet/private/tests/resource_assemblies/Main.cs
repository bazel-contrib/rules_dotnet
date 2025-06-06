namespace ResourceAssembliesTest
{
    using System;
    using Humanizer;
    using System.Globalization;

    class Program
    {
        static void Main(string[] args)
        {
            var outputFile = args[0];
            if (string.IsNullOrEmpty(outputFile))
            {
                throw new ArgumentException("Output file path must be provided as the first argument.");
            }

            var date = DateTime.Now.AddYears(1);
            var dateStringEnglish = date.Humanize(culture: CultureInfo.GetCultureInfo("en-US"));
            var dateStringGerman = date.Humanize(culture: CultureInfo.GetCultureInfo("de-DE"));
            var dateStringSpanish = date.Humanize(culture: CultureInfo.GetCultureInfo("es-ES"));

            var cwd = System.IO.Directory.GetCurrentDirectory();
            using (var writer = new System.IO.StreamWriter(outputFile))
            {
                writer.WriteLine($"English: {dateStringEnglish}");
                writer.WriteLine($"German: {dateStringGerman}");
                writer.WriteLine($"Spanish: {dateStringSpanish}");
            }
        }
    }
}
