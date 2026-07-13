using System.Globalization;
using System.Resources;

namespace Localization
{
    public static class Greeter
    {
        // The manifest name is "<assembly>.Strings"; this library is built with
        // `out = "Localization"`, so the neutral resource is "Localization.Strings".
        private static readonly ResourceManager Rm =
            new ResourceManager("Localization.Strings", typeof(Greeter).Assembly);

        public static string Hello(string culture) =>
            Rm.GetString("Hello", CultureInfo.GetCultureInfo(culture)) ?? "<missing>";
    }
}
