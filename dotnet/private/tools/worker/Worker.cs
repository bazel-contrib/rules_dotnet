#nullable enable

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;

namespace RulesDotnet
{
    /// <summary>
    /// Bazel's JSON persistent worker protocol, and the child process plumbing
    /// the C# and F# compiler workers share.
    /// </summary>
    internal static class Worker
    {
        /// <summary>
        /// Compiles one request, appending whatever the compiler said to
        /// <paramref name="output"/> and returning its exit code.
        /// </summary>
        public delegate int Compilation(List<string> arguments, StringBuilder output);

        private static readonly JsonSerializerOptions JsonOptions = new JsonSerializerOptions
        {
            PropertyNameCaseInsensitive = true,
        };

        /// <summary>The compilers only read a response file as UTF-8 if it starts with a BOM.</summary>
        private static readonly Encoding Utf8WithBom = new UTF8Encoding(encoderShouldEmitUTF8Identifier: true);

        /// <summary>Removes <paramref name="flag"/> from <paramref name="arguments"/> and reports whether it was there.</summary>
        public static bool TakeFlag(List<string> arguments, string flag) =>
            arguments.RemoveAll(argument => argument == flag) > 0;

        /// <summary>
        /// Returns <paramref name="arguments"/> with every input that is a symlink
        /// -- an argument starting with one of <paramref name="prefixes"/>, such as
        /// a reference or an analyzer -- pointed at the file behind the link.
        /// </summary>
        /// <remarks>
        /// A sandboxed worker, which path mapping always makes it, is handed its
        /// inputs as links in a directory of its own, which Bazel stages again for
        /// every request. Neither compiler copes with that:
        ///
        /// Both keep what they read from a reference for as long as its full path
        /// and last-write time stay the same -- fsc inside the F# worker, Roslyn
        /// inside its build server -- and on Unix that time is the link's own, not
        /// its target's. A link stays for as long as it points at the same output,
        /// so a rebuilt reference keeps its old time and the next compile is handed
        /// its old contents. The target's time moves with every rebuild.
        ///
        /// Roslyn's build server also keeps the analyzers it loaded, and finds the
        /// assemblies an analyzer loads through the paths it was handed earlier,
        /// whichever worker's directory they were in. Once that directory is staged
        /// for another request, or the worker is gone, a compile loading the
        /// analyzer from elsewhere -- another configuration's outputs -- fails to
        /// load them. The target's path stays.
        ///
        /// The outputs are the same either way: the compilers record neither
        /// reference nor analyzer paths in them.
        /// </remarks>
        public static List<string> ResolveInputLinks(List<string> arguments, params string[] prefixes)
        {
            var resolved = new List<string>(arguments.Count);
            foreach (var argument in arguments)
            {
                resolved.Add(ResolveInputLink(argument, prefixes));
            }

            return resolved;
        }

        /// <summary>The full path of the file behind <paramref name="path"/>, or of the path itself when it is no link.</summary>
        private static string ResolvePath(string path)
        {
            try
            {
                return File.ResolveLinkTarget(path, returnFinalTarget: true)?.FullName ?? Path.GetFullPath(path);
            }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException)
            {
                return Path.GetFullPath(path);
            }
        }

        private static string ResolveInputLink(string argument, string[] prefixes)
        {
            foreach (var prefix in prefixes)
            {
                if (!argument.StartsWith(prefix, StringComparison.Ordinal))
                {
                    continue;
                }

                // csc splits a response file line on whitespace, so its paths come
                // quoted, and go back quoted.
                var path = argument[prefix.Length..];
                var quoted = path.Length >= 2 && path[0] == '"' && path[^1] == '"';
                if (quoted)
                {
                    path = path[1..^1];
                }

                try
                {
                    var target = File.ResolveLinkTarget(path, returnFinalTarget: true);
                    if (target == null)
                    {
                        return argument;
                    }

                    return prefix + (quoted ? "\"" + target.FullName + "\"" : target.FullName);
                }
                catch (Exception e) when (e is IOException or UnauthorizedAccessException)
                {
                    // Missing or unreadable: the compiler reports it by the name it was given.
                    return argument;
                }
            }

            return argument;
        }

        /// <summary>
        /// Serves work requests on stdin and stdout until the stream closes. One
        /// at a time: the compile actions ask for <c>supports-workers</c>, not for
        /// multiplexing.
        /// </summary>
        public static int RunWorkerLoop(Compilation compile)
        {
            using var stdin = Console.OpenStandardInput();
            using var stdout = Console.OpenStandardOutput();

            var pending = new List<byte>();
            while (ReadRequest(stdin, pending) is { } request)
            {
                var arguments = ExpandResponseFiles(request.Arguments ?? new List<string>());
                var output = new StringBuilder();
                int exitCode;
                try
                {
                    exitCode = compile(arguments, output);
                }
                catch (Exception e)
                {
                    // One bad request must not take the worker down with it.
                    output.AppendLine(e.ToString());
                    exitCode = 1;
                }

                WriteResponse(stdout, request.RequestId, exitCode, output.ToString());
            }

            return 0;
        }

        /// <summary>Runs a single compilation, reporting the way a plain action does.</summary>
        public static int RunOnce(Compilation compile, List<string> arguments)
        {
            var output = new StringBuilder();
            var exitCode = compile(ExpandResponseFiles(arguments), output);
            Console.Error.Write(output.ToString());
            return exitCode;
        }

        /// <summary>
        /// Runs <c>dotnet &lt;compiler&gt; [flags] @&lt;response file&gt; &lt;pathmap&gt;</c>
        /// and appends everything it writes to <paramref name="output"/>.
        /// </summary>
        /// <remarks>
        /// The compiler arguments go back into a response file, one per line,
        /// because a compile carrying the targeting pack's references is far past
        /// the 32767 characters Windows allows on a command line. The pathmap is
        /// built here rather than at analysis time, because the compilers embed
        /// absolute paths into their output and the execution root is not known
        /// until now.
        /// </remarks>
        public static int RunCompiler(
            string dotnet,
            string compiler,
            IEnumerable<string> flags,
            List<string> arguments,
            string pathMapFlag,
            StringBuilder output)
        {
            var startInfo = new ProcessStartInfo
            {
                FileName = dotnet,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
            };

            // Roslyn's build server finds the runtime it loads its assemblies from
            // through the DOTNET_ROOT it starts with, and outlives the worker that
            // started it: under this worker's directory, which Bazel stages again
            // or removes, that runtime goes missing for every compile it serves.
            // The file behind the link stays.
            startInfo.Environment["DOTNET_ROOT"] = Path.GetDirectoryName(ResolvePath(dotnet));

            startInfo.ArgumentList.Add(compiler);
            foreach (var flag in flags)
            {
                startInfo.ArgumentList.Add(flag);
            }

            var responseFile = Path.Combine(Path.GetTempPath(), Path.GetRandomFileName() + ".rsp");
            File.WriteAllLines(responseFile, arguments, Utf8WithBom);
            startInfo.ArgumentList.Add("@" + responseFile);
            startInfo.ArgumentList.Add(pathMapFlag + Directory.GetCurrentDirectory() + "=.");

            try
            {
                using var process = Process.Start(startInfo);
                if (process == null)
                {
                    output.AppendLine("failed to start " + dotnet);
                    return 1;
                }

                // Drain both pipes at once: filling one while blocked on the other deadlocks.
                var standardOutput = process.StandardOutput.ReadToEndAsync();
                var standardError = process.StandardError.ReadToEndAsync();
                output.Append(standardOutput.GetAwaiter().GetResult());
                output.Append(standardError.GetAwaiter().GetResult());
                process.WaitForExit();

                return process.ExitCode;
            }
            finally
            {
                // Never let a failed cleanup replace the compilation's own error.
                try
                {
                    File.Delete(responseFile);
                }
                catch (IOException)
                {
                }
            }
        }

        /// <summary>
        /// Inlines any <c>@file</c> argument. Bazel expands the response file into
        /// the request itself under the worker protocol, but passes it through as
        /// <c>@file</c> when the worker runs as a plain action, and the compilers
        /// only want to deal with one of those shapes.
        /// </summary>
        private static List<string> ExpandResponseFiles(List<string> arguments)
        {
            var expanded = new List<string>(arguments.Count);
            foreach (var argument in arguments)
            {
                if (argument.StartsWith('@') && File.Exists(argument[1..]))
                {
                    expanded.AddRange(File.ReadAllLines(argument[1..]));
                }
                else
                {
                    expanded.Add(argument);
                }
            }

            return expanded;
        }

        private sealed class WorkRequest
        {
            public int RequestId { get; set; }

            public List<string>? Arguments { get; set; }
        }

        /// <summary>
        /// Reads the next work request, or null at end of stream. Bazel's JSON
        /// worker protocol writes the objects back to back with no delimiter
        /// between them, so <paramref name="pending"/> carries whatever was read
        /// past the end of the last one.
        /// </summary>
        private static WorkRequest? ReadRequest(Stream stream, List<byte> pending)
        {
            Span<byte> chunk = stackalloc byte[8192];

            while (true)
            {
                if (TryTakeRequest(pending, out var request))
                {
                    return request;
                }

                var read = stream.Read(chunk);
                if (read <= 0)
                {
                    return null;
                }

                pending.AddRange(chunk[..read]);
            }
        }

        private static bool TryTakeRequest(List<byte> pending, out WorkRequest? request)
        {
            // isFinalBlock: false makes a half-received object a "not yet", rather
            // than a parse error.
            var reader = new Utf8JsonReader(CollectionsMarshal.AsSpan(pending), isFinalBlock: false, state: default);
            if (!JsonDocument.TryParseValue(ref reader, out var document))
            {
                request = null;
                return false;
            }

            using (document)
            {
                request = document.RootElement.Deserialize<WorkRequest>(JsonOptions);
            }

            pending.RemoveRange(0, (int)reader.BytesConsumed);
            return true;
        }

        private static void WriteResponse(Stream stdout, int requestId, int exitCode, string output)
        {
            using var writer = new Utf8JsonWriter(stdout, new JsonWriterOptions { SkipValidation = true });
            writer.WriteStartObject();
            writer.WriteNumber("exitCode", exitCode);
            writer.WriteString("output", output);
            writer.WriteNumber("requestId", requestId);
            writer.WriteEndObject();
            writer.Flush();
            stdout.Flush();
        }
    }
}
