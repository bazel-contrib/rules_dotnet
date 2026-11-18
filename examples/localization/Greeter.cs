using System.Globalization;
using System.Resources;

namespace Localization
{
    public static class Greeter
    {
        // `root_namespace` + file name.
        private static readonly ResourceManager Rm =
            new ResourceManager("Localization.Strings", typeof(Greeter).Assembly);

        public static string Hello(string culture) =>
            Rm.GetString("Hello", CultureInfo.GetCultureInfo(culture)) ?? "<missing>";
    }
}
