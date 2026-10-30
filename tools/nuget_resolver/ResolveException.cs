using System;

namespace NuGetResolver;

/// <summary>
/// A resolution failure whose message is shown to the user verbatim.
/// </summary>
public sealed class ResolveException : Exception
{
    public ResolveException(string message)
        : base(message)
    {
    }
}
