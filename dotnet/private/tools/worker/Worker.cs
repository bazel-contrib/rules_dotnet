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
        /// A sandboxed worker is handed its inputs as links in a directory Bazel
        /// restages for every request, and the compilers cache across requests.
        /// fsc and Roslyn's build server key a reference by path and last-write
        /// time, which on Unix is the link's own, so a rebuilt reference would keep
        /// its old contents. The build server, which outlives the worker, also loads
        /// an analyzer's dependencies through paths from earlier requests, which may
        /// no longer exist. The files behind the links have neither problem, and
        /// the compilers record none of these paths in their outputs.
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

        /// <summary>
        /// <paramref name="path"/> without the quotes csc's response file needs,
        /// since csc splits each of its lines on whitespace.
        /// </summary>
        public static string Unquote(string path) =>
            path.Length >= 2 && path[0] == '"' && path[^1] == '"' ? path[1..^1] : path;

        /// <summary>The full path of the file behind <paramref name="path"/>, or null when it is no link or cannot be read.</summary>
        private static string? LinkTarget(string path)
        {
            try
            {
                return File.ResolveLinkTarget(path, returnFinalTarget: true)?.FullName;
            }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException)
            {
                return null;
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

                var value = argument[prefix.Length..];
                var path = Unquote(value);

                // Left as given when missing, so the compiler reports it by that name.
                var target = LinkTarget(path);
                if (target == null)
                {
                    return argument;
                }

                return prefix + (path.Length == value.Length ? target : "\"" + target + "\"");
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
            return RunWorkerLoop(compile, stdin, stdout, Console.Error);
        }

        /// <summary>
        /// Serves the work requests in <paramref name="requests"/>, writing a
        /// response for each to <paramref name="responses"/>. Returns 0 once the
        /// requests run out, or 1, with the reason on <paramref name="errors"/>, when
        /// they are not JSON work requests.
        /// </summary>
        public static int RunWorkerLoop(Compilation compile, Stream requests, Stream responses, TextWriter errors)
        {
            var pending = new List<byte>();
            while (true)
            {
                WorkRequest? request;
                try
                {
                    request = ReadRequest(requests, pending);
                }
                catch (JsonException e)
                {
                    // Nothing can be answered: a reply Bazel can read needs the
                    // protocol it is speaking.
                    errors.WriteLine(
                        "error: the compiler worker read something other than a JSON work request (" + e.Message +
                        "). It speaks only Bazel's JSON worker protocol, which its actions ask for with " +
                        "requires-worker-protocol=json. An executor that runs it as a remote persistent worker " +
                        "has to be told to send JSON, for example with the platform property " +
                        "persistentWorkerProtocol=json.");
                    return 1;
                }

                if (request == null)
                {
                    return 0;
                }

                var arguments = ExpandResponseFiles(request.Arguments ?? new List<string>());
                var output = new StringBuilder();

                // One bad request must not take the worker down with it.
                var exitCode = CompileOrFail(compile, arguments, output);

                WriteResponse(responses, request.RequestId, exitCode, output.ToString());
            }
        }

        /// <summary>Runs a single compilation, reporting the way a plain action does.</summary>
        public static int RunOnce(Compilation compile, List<string> arguments)
        {
            var output = new StringBuilder();

            // An exception left unhandled would end the process before the
            // compiler's own diagnostics, already captured, were ever printed.
            var exitCode = CompileOrFail(compile, ExpandResponseFiles(arguments), output);

            Console.Error.Write(output.ToString());
            return exitCode;
        }

        /// <summary>
        /// Runs <paramref name="compile"/>, and turns an exception it throws into a
        /// failed compilation: exit code 1, with the exception after whatever the
        /// compiler had said by then.
        /// </summary>
        private static int CompileOrFail(Compilation compile, List<string> arguments, StringBuilder output)
        {
            try
            {
                return compile(arguments, output);
            }
            catch (Exception e)
            {
                output.AppendLine(e.ToString());
                return 1;
            }
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

            // Roslyn's build server needs the runtime of the SDK it ships in, which
            // may be newer than the one this worker runs on, and it outlives this
            // worker, whose directory Bazel restages. csc gives the server the
            // directory of DOTNET_HOST_PATH as its DOTNET_ROOT; without one, the
            // directory behind a `dotnet` link in the working directory, such as an
            // execution root's link to a source folder of that name; and only then
            // its own DOTNET_ROOT. A server that cannot load its runtime never
            // starts, and every compile waits 20 s for it before compiling alone.
            var host = LinkTarget(dotnet) ?? Path.GetFullPath(dotnet);
            startInfo.Environment["DOTNET_HOST_PATH"] = host;
            startInfo.Environment["DOTNET_ROOT"] = Path.GetDirectoryName(host);

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
                request = document.RootElement.Deserialize<WorkRequest>(JsonOptions) ??
                          throw new JsonException("a work request is an object, not null");
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
