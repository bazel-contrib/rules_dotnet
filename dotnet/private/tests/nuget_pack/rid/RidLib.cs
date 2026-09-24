namespace RulesDotnet.Tests.NuGetPack
{
    /// <summary>Differs per runtime identifier through a select on its sources.</summary>
    public static class RidLib
    {
        /// <summary>Which runtime this build is for.</summary>
        public static string Runtime => Platform.Name;
    }
}
