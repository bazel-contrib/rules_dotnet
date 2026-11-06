using System;
using System.IO;
using System.Security.Cryptography;

internal static class KeyGen
{
    public static int Main(string[] args)
    {
        using var rsa = new RSACryptoServiceProvider(1024);
        File.WriteAllBytes(args[0], rsa.ExportCspBlob(includePrivateParameters: true));
        return 0;
    }
}
