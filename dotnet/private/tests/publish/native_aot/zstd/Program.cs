using System;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Text;

namespace AotZstd
{
    public static class Program
    {
        public static int Main()
        {
            // Only an application that compresses with zstd links the library,
            // so this is what finds out whether it is there to link.
            var original = Encoding.UTF8.GetBytes(string.Concat(Enumerable.Repeat("rules_dotnet ", 1000)));
            var compressed = new MemoryStream();
            using (var zstd = new ZstandardStream(compressed, CompressionMode.Compress, leaveOpen: true))
            {
                zstd.Write(original);
            }

            var compressedLength = compressed.Length;
            compressed.Position = 0;
            var decompressed = new MemoryStream();
            using (var zstd = new ZstandardStream(compressed, CompressionMode.Decompress))
            {
                zstd.CopyTo(decompressed);
            }

            Console.WriteLine("zstd: {0} bytes, compressed to {1}", original.Length, compressedLength);
            if (!decompressed.ToArray().SequenceEqual(original))
            {
                Console.WriteLine("zstd did not give back what it was given");
                return 1;
            }

            // A stack trace names its methods only if ilc emitted the data for it.
            try
            {
                Throw();
            }
            catch (InvalidOperationException e)
            {
                Console.WriteLine(e.StackTrace);
                if (e.StackTrace == null || !e.StackTrace.Contains(nameof(Throw)))
                {
                    Console.WriteLine("the stack trace does not name the method that threw");
                    return 2;
                }
            }

            // Debuggers and dump tools find the runtime through this symbol, which
            // they look up among the executable's exports.
            if (!NativeLibrary.TryGetExport(NativeLibrary.GetMainProgramHandle(), "DotNetRuntimeContractDescriptor", out _))
            {
                Console.WriteLine("the executable does not export DotNetRuntimeContractDescriptor");
                return 3;
            }

            return 0;
        }

        [MethodImpl(MethodImplOptions.NoInlining)]
        private static void Throw() => throw new InvalidOperationException("thrown to read the stack trace");
    }
}
