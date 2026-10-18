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

        // Local folder feeds have no host to authenticate against; only
        // absolute HTTP(S) sources can carry netrc credentials.
        if (!Uri.TryCreate(source, UriKind.Absolute, out var uri) ||
            (uri.Scheme != Uri.UriSchemeHttp && uri.Scheme != Uri.UriSchemeHttps))
        {
            return packageSource;
        }

        _netrcPath = netrcPath;
        var credential = CredentialsFor(uri);
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
                        // A new machine ends the previous stanza, so only now
                        // are its login/password guaranteed fully read.
                        if (Matches(machine, login, url))
                        {
                            return new NetworkCredential(login, password ?? string.Empty);
                        }
                        machine = parts[i + 1];
                        login = null;
                        password = null;
                        break;
                    case "login":
                        login = parts[i + 1];
                        break;
                    case "password":
                        password = parts[i + 1];
                        break;
                }
            }
        }

        if (Matches(machine, login, url))
        {
            return new NetworkCredential(login, password ?? string.Empty);
        }

        return null;
    }

    private static bool Matches(string? machine, string? login, Uri url)
        => machine != null &&
           string.Equals(machine, url.Host, StringComparison.OrdinalIgnoreCase) &&
           login != null;
}
