namespace Example
{
    /// <summary>Names the runtime this assembly was built for.</summary>
    public static class Platform
    {
        /// <summary>The runtime identifier this build targets.</summary>
        public static string RuntimeIdentifier => PlatformName.Value;
    }
}
