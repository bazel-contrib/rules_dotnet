using System;
using System.IO;
using System.Net;
using NuGet.Configuration;

namespace NuGetResolver;

/// <summary>
/// Reads per-host credentials from a netrc file and applies them to the
/// package sources the resolver talks to.
/// </summary>
public static class Netrc
{
    private static string? _netrcPath;

    /// <summary>Returns the source with netrc credentials applied, when the netrc covers its host.</summary>
    public static PackageSource ApplyCredentials(string source, string? netrcPath)
    {
        var packageSource = new PackageSource(source);
        if (netrcPath == null)
        {
            return packageSource;
        }

        _netrcPath = netrcPath;
        var credential = CredentialsFor(new Uri(source));
        if (credential != null)
        {
            packageSource.Credentials = new PackageSourceCredential(
                source,
                credential.UserName,
                credential.Password,
                isPasswordClearText: true,
                validAuthenticationTypesText: null);
        }

        return packageSource;
    }

    /// <summary>The credentials the netrc records for the host of url, or null.</summary>
    public static NetworkCredential? CredentialsFor(Uri url)
    {
        if (_netrcPath == null || !File.Exists(_netrcPath))
        {
            return null;
        }

        string? machine = null, login = null, password = null;
        foreach (var rawLine in File.ReadLines(_netrcPath))
        {
            var parts = rawLine.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
            for (var i = 0; i + 1 < parts.Length; i += 2)
            {
                switch (parts[i])
                {
                    case "machine":
                        machine = parts[i + 1];
                        break;
                    case "login":
                        login = parts[i + 1];
                        break;
                    case "password":
                        password = parts[i + 1];
                        break;
                }
            }

            if (machine != null &&
                string.Equals(machine, url.Host, StringComparison.OrdinalIgnoreCase) &&
                login != null)
            {
                return new NetworkCredential(login, password ?? string.Empty);
            }
        }

        return null;
    }
}
