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
    /// Bazel's persistent worker protocol, in both its JSON and its protobuf
    /// encoding, and the child process plumbing the C# and F# compiler workers
    /// share.
    /// </summary>
    internal static class Worker
    {
        // The protobuf wire types a work request can use:
        // https://protobuf.dev/programming-guides/encoding/#structure
        private const int Varint = 0;
        private const int Fixed64 = 1;
        private const int LengthDelimited = 2;
        private const int Fixed32 = 5;

        // The fields of Bazel's worker_protocol.proto this worker reads and writes.
        private const int WorkRequestArguments = 1;
        private const int WorkRequestRequestId = 3;
        private const int WorkResponseExitCode = 1;
        private const int WorkResponseOutput = 2;
        private const int WorkResponseRequestId = 3;

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
        /// response for each to <paramref name="responses"/> in the encoding the
        /// requests came in. Returns 0 once the requests run out, or 1, with the
        /// reason on <paramref name="errors"/>, when one cannot be read.
        /// </summary>
        public static int RunWorkerLoop(Compilation compile, Stream requests, Stream responses, TextWriter errors)
        {
            var pending = new List<byte>();
            if (DetectProtocol(requests, pending) is not { } protocol)
            {
                return 0;
            }

            while (true)
            {
                WorkRequest? request;
                try
                {
                    request = ReadRequest(requests, pending, protocol);
                }
                catch (Exception e) when (e is JsonException or InvalidDataException)
                {
                    // Nothing can be answered: a reply Bazel can match up needs the
                    // request it answers.
                    errors.WriteLine(
                        "error: the compiler worker could not read a " + (protocol == Protocol.Json ? "JSON" : "protobuf") +
                        " work request (" + e.Message + "). It speaks Bazel's worker protocol in JSON and in " +
                        "protobuf, and takes the encoding from the first byte it reads: '{' for JSON, anything " +
                        "else for length-delimited protobuf.");
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

                if (protocol == Protocol.Json)
                {
                    WriteJsonResponse(responses, request.RequestId, exitCode, output.ToString());
                }
                else
                {
                    WriteProtobufResponse(responses, request.RequestId, exitCode, output.ToString());
                }
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
        /// Points a compiler at a directory where the runtime can keep the state
        /// of its named mutexes, which csc and Roslyn's build server coordinate
        /// through.
        /// </summary>
        /// <remarks>
        /// From .NET 11 that state is the user's own. On Linux it lives under
        /// XDG_RUNTIME_DIR, or else under HOME, and on macOS under TMPDIR, which
        /// the runtime will not follow a link to reach. A sandbox or a remote
        /// executor can leave HOME unwritable, and a test's TMPDIR is /tmp, which
        /// on macOS is a link. Either fails every named mutex in the process: csc
        /// then compiles on its own instead of on the build server, every time.
        /// The directory on Linux is the same for every worker of the user, so
        /// that they all see the server one of them started.
        /// </remarks>
        internal static void GiveNamedMutexesADirectory(IDictionary<string, string?> environment)
        {
            try
            {
                if (OperatingSystem.IsLinux() && string.IsNullOrEmpty(environment.TryGetValue("XDG_RUNTIME_DIR", out var runtime) ? runtime : null))
                {
                    var directory = Path.Combine(Path.GetTempPath(), "rules_dotnet-" + Environment.UserName);
                    Directory.CreateDirectory(directory, UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute);
                    environment["XDG_RUNTIME_DIR"] = directory;
                }
                else if (OperatingSystem.IsMacOS())
                {
                    var temp = environment.TryGetValue("TMPDIR", out var value) && !string.IsNullOrEmpty(value) ? value : "/tmp";
                    var target = new DirectoryInfo(temp.TrimEnd('/')).ResolveLinkTarget(returnFinalTarget: true);
                    if (target != null)
                    {
                        environment["TMPDIR"] = target.FullName;
                    }
                }
            }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException or ArgumentException)
            {
                // The runtime's own choice stands; csc falls back to compiling on
                // its own if that fails too, as it would without this.
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
            GiveNamedMutexesADirectory(startInfo.Environment);

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

        /// <summary>The two encodings of Bazel's worker protocol.</summary>
        private enum Protocol
        {
            Json,
            Protobuf,
        }

        private sealed class WorkRequest
        {
            public int RequestId { get; set; }

            public List<string>? Arguments { get; set; }
        }

        /// <summary>
        /// Tells the encoding of the work requests from the first byte of the
        /// first one, or returns null when the stream ends before it.
        /// </summary>
        /// <remarks>
        /// The encoding is Bazel's choice when it runs the worker, but a remote
        /// executor's when it does, and nothing tells the worker which. A JSON
        /// request is an object, written with nothing before it, so it starts with
        /// <c>{</c>. A protobuf request starts with its length as a varint, which
        /// is that byte only for a message of exactly 123 bytes. No compile
        /// request is that short: the smallest, a satellite assembly's, takes more
        /// than that for its output and its fixed flags alone.
        /// </remarks>
        private static Protocol? DetectProtocol(Stream stream, List<byte> pending)
        {
            while (pending.Count == 0)
            {
                if (!ReadMore(stream, pending))
                {
                    return null;
                }
            }

            return pending[0] == (byte)'{' ? Protocol.Json : Protocol.Protobuf;
        }

        /// <summary>
        /// Reads the next work request, or null once the stream ends between two.
        /// <paramref name="pending"/> carries whatever was read past the end of
        /// the last one, since nothing marks where a JSON request ends but the
        /// object closing.
        /// </summary>
        private static WorkRequest? ReadRequest(Stream stream, List<byte> pending, Protocol protocol)
        {
            while (true)
            {
                var request = protocol == Protocol.Json ? TakeJsonRequest(pending) : TakeProtobufRequest(pending);
                if (request != null)
                {
                    return request;
                }

                if (!ReadMore(stream, pending))
                {
                    // Nothing may follow the last request but, in JSON, the line
                    // break a writer can end it with.
                    if (pending.Count == 0 ||
                        (protocol == Protocol.Json && pending.TrueForAll(b => (char)b is ' ' or '\t' or '\r' or '\n')))
                    {
                        return null;
                    }

                    throw new InvalidDataException("the input ended partway through a work request");
                }
            }
        }

        /// <summary>Appends what <paramref name="stream"/> has next to <paramref name="pending"/>, or returns false at its end.</summary>
        private static bool ReadMore(Stream stream, List<byte> pending)
        {
            Span<byte> chunk = stackalloc byte[8192];
            var read = stream.Read(chunk);
            if (read <= 0)
            {
                return false;
            }

            pending.AddRange(chunk[..read]);
            return true;
        }

        /// <summary>Takes a JSON work request off the front of <paramref name="pending"/>, or returns null while it is incomplete.</summary>
        private static WorkRequest? TakeJsonRequest(List<byte> pending)
        {
            // isFinalBlock: false makes a half-received object a "not yet", rather
            // than a parse error.
            var reader = new Utf8JsonReader(CollectionsMarshal.AsSpan(pending), isFinalBlock: false, state: default);
            if (!JsonDocument.TryParseValue(ref reader, out var document))
            {
                return null;
            }

            WorkRequest request;
            using (document)
            {
                request = document.RootElement.Deserialize<WorkRequest>(JsonOptions) ??
                          throw new JsonException("a work request is an object, not null");
            }

            pending.RemoveRange(0, (int)reader.BytesConsumed);
            return request;
        }

        /// <summary>
        /// Takes a <c>WorkRequest</c> message, preceded by its length as a varint,
        /// off the front of <paramref name="pending"/>, or returns null while it is
        /// incomplete.
        /// </summary>
        private static WorkRequest? TakeProtobufRequest(List<byte> pending)
        {
            var frame = new ProtobufReader(CollectionsMarshal.AsSpan(pending));
            if (!frame.TryReadVarint(out var length))
            {
                return null;
            }

            if (length > int.MaxValue)
            {
                throw new InvalidDataException("a work request cannot be " + length + " bytes long");
            }

            if (frame.Remaining < (int)length)
            {
                return null;
            }

            var request = ParseWorkRequest(CollectionsMarshal.AsSpan(pending).Slice(frame.Position, (int)length));
            pending.RemoveRange(0, frame.Position + (int)length);
            return request;
        }

        /// <summary>
        /// Reads the fields of a <c>WorkRequest</c> this worker needs:
        /// https://github.com/bazelbuild/bazel/blob/master/src/main/protobuf/worker_protocol.proto
        /// </summary>
        private static WorkRequest ParseWorkRequest(ReadOnlySpan<byte> message)
        {
            var arguments = new List<string>();
            var requestId = 0;
            var reader = new ProtobufReader(message);
            while (!reader.AtEnd)
            {
                var (field, wireType) = reader.ReadTag();
                if (field == WorkRequestArguments && wireType == LengthDelimited)
                {
                    arguments.Add(Encoding.UTF8.GetString(reader.ReadLengthDelimited()));
                }
                else if (field == WorkRequestRequestId && wireType == Varint)
                {
                    // An int32 is the low 32 bits of the varint.
                    requestId = unchecked((int)reader.ReadVarint());
                }
                else
                {
                    // The inputs and their digests, cancel, verbosity and
                    // sandbox_dir, none of which a worker that neither multiplexes
                    // nor cancels needs, and any field added after them.
                    reader.Skip(wireType);
                }
            }

            return new WorkRequest { RequestId = requestId, Arguments = arguments };
        }

        private static void WriteJsonResponse(Stream stdout, int requestId, int exitCode, string output)
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

        /// <summary>
        /// Writes a <c>WorkResponse</c> message, preceded by its length as a
        /// varint. Fields at their default value are left out, as protobuf does.
        /// </summary>
        private static void WriteProtobufResponse(Stream stdout, int requestId, int exitCode, string output)
        {
            var message = new List<byte>();
            if (exitCode != 0)
            {
                WriteVarint(message, WorkResponseExitCode << 3 | Varint);

                // A negative int32, such as a Windows NTSTATUS, is sign-extended to ten bytes.
                WriteVarint(message, unchecked((ulong)(long)exitCode));
            }

            if (output.Length > 0)
            {
                var bytes = Encoding.UTF8.GetBytes(output);
                WriteVarint(message, WorkResponseOutput << 3 | LengthDelimited);
                WriteVarint(message, (ulong)bytes.Length);
                message.AddRange(bytes);
            }

            if (requestId != 0)
            {
                WriteVarint(message, WorkResponseRequestId << 3 | Varint);
                WriteVarint(message, unchecked((ulong)(long)requestId));
            }

            var frame = new List<byte>(message.Count + 5);
            WriteVarint(frame, (ulong)message.Count);
            frame.AddRange(message);

            stdout.Write(CollectionsMarshal.AsSpan(frame));
            stdout.Flush();
        }

        private static void WriteVarint(List<byte> bytes, ulong value)
        {
            while (value >= 0x80)
            {
                bytes.Add((byte)(value | 0x80));
                value >>= 7;
            }

            bytes.Add((byte)value);
        }

        /// <summary>
        /// Reads the protobuf wire format, as much of it as a work request uses:
        /// https://protobuf.dev/programming-guides/encoding/
        /// </summary>
        private ref struct ProtobufReader
        {
            private readonly ReadOnlySpan<byte> _data;

            public ProtobufReader(ReadOnlySpan<byte> data)
            {
                _data = data;
                Position = 0;
            }

            public int Position { get; private set; }

            public readonly int Remaining => _data.Length - Position;

            public readonly bool AtEnd => Position == _data.Length;

            /// <summary>Reads a varint, or returns false when the data ends before it does.</summary>
            public bool TryReadVarint(out ulong value)
            {
                value = 0;
                for (var shift = 0; shift < 64; shift += 7)
                {
                    if (AtEnd)
                    {
                        return false;
                    }

                    var b = _data[Position++];
                    value |= (ulong)(b & 0x7F) << shift;
                    if (b < 0x80)
                    {
                        return true;
                    }
                }

                throw new InvalidDataException("a varint runs past ten bytes");
            }

            public ulong ReadVarint() =>
                TryReadVarint(out var value) ? value : throw Truncated();

            public (int Field, int WireType) ReadTag()
            {
                var tag = ReadVarint();
                var field = tag >> 3;
                if (field == 0 || field > int.MaxValue)
                {
                    throw new InvalidDataException("a work request has no field " + field);
                }

                return ((int)field, (int)(tag & 7));
            }

            public ReadOnlySpan<byte> ReadLengthDelimited()
            {
                var length = ReadVarint();
                if (length > (ulong)Remaining)
                {
                    throw Truncated();
                }

                var value = _data.Slice(Position, (int)length);
                Position += (int)length;
                return value;
            }

            public void Skip(int wireType)
            {
                switch (wireType)
                {
                    case Varint:
                        ReadVarint();
                        break;
                    case Fixed64:
                        Advance(8);
                        break;
                    case LengthDelimited:
                        ReadLengthDelimited();
                        break;
                    case Fixed32:
                        Advance(4);
                        break;
                    default:
                        // 3 and 4, the start and end of a group, which proto3 has no use for.
                        throw new InvalidDataException("a work request has no fields of wire type " + wireType);
                }
            }

            private void Advance(int count)
            {
                if (count > Remaining)
                {
                    throw Truncated();
                }

                Position += count;
            }

            private static InvalidDataException Truncated() =>
                new InvalidDataException("a work request ends partway through a field");
        }
    }
}
