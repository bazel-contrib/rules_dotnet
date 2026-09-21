// Conversion to Webcil, the container a Blazor WebAssembly application's
// assemblies are served as.
//
// A `.dll` over HTTP is blocked or rewritten often enough - by proxies, CDNs
// and corporate filters - that Blazor stopped shipping them. Webcil holds the
// same metadata inside a WebAssembly module, so what the browser downloads has
// a `.wasm` extension and an unremarkable header.

using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
using System.Threading.Tasks;

internal static class Webcil
{
    private const string ConverterType = "Microsoft.NET.WebAssembly.Webcil.WebcilConverter";

    public static void ConvertAll(string converterAssembly, List<FileMapping> assemblies)
    {
        if (assemblies.Count == 0)
        {
            return;
        }

        var type = Tasks.Load(converterAssembly).GetType(ConverterType)
            ?? throw new InvalidOperationException($"{ConverterType} is missing from {converterAssembly}");

        var create = type.GetMethod("FromPortableExecutable", BindingFlags.Public | BindingFlags.Static)!;
        var wrap = type.GetProperty("WrapInWebAssembly")!;
        var convert = type.GetMethod("ConvertToWebcil", BindingFlags.Public | BindingFlags.Instance)!;

        Parallel.ForEach(assemblies, assembly =>
        {
            Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(assembly.Output))!);

            var converter = create.Invoke(
                null,
                new object[] { Path.GetFullPath(assembly.Source), Path.GetFullPath(assembly.Output) })!;

            // Wrapping is what makes the result a WebAssembly module rather
            // than a bare Webcil payload, which is what the browser loads.
            wrap.SetValue(converter, true);
            convert.Invoke(converter, null);
        });
    }
}
