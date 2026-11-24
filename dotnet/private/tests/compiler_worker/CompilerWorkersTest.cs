#nullable enable

using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Reflection.PortableExecutable;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using Bazel;
using NUnit.Framework;

namespace RulesDotnet.Tests;

/// <summary>
/// Runs the compiler workers the rules build, with the toolchain's SDK, over
/// Bazel's worker protocol.
/// </summary>
[TestFixture]
[NonParallelizable]
public class CompilerWorkersTest
{
    private static readonly TimeSpan ResponseTimeout = TimeSpan.FromMinutes(2);

    private string _dotnet = "";
    private string _csc = "";
    private string _fsc = "";
    private string _csharpWorker = "";
    private string _fsharpWorker = "";
    private string _sharedFramework = "";
    private string _directory = "";
    private readonly List<int> _servers = new();

    [OneTimeSetUp]
    public void FindTheToolchainAndTheWorkers()
    {
        var runfiles = Runfiles.Create();

        // The toolchain's variables are execution paths, `external/<repo>/...`.
        string FromToolchain(string variable) =>
            runfiles.Rlocation(Environment.GetEnvironmentVariable(variable)!.Replace("external/", ""));

        // A worker's runfiles path is its launcher's, `<name>.dll.sh` or
        // `<name>.dll.bat`, and the assembly is beside it.
        string WorkerDll(string variable)
        {
            var launcher = Environment.GetEnvironmentVariable(variable)!;
            var assembly = launcher[..launcher.LastIndexOf('.')];
            Assert.That(assembly, Does.EndWith(".dll"));
            return runfiles.Rlocation(assembly);
        }

        _dotnet = FromToolchain("DOTNET_BIN");
        _csc = FromToolchain("CSC_BIN");
        _fsc = FromToolchain("FSC_BIN");
        _csharpWorker = WorkerDll("CSHARP_COMPILER_WORKER");
        _fsharpWorker = WorkerDll("FSHARP_COMPILER_WORKER");
        _sharedFramework = Directory
            .GetDirectories(Path.Combine(Path.GetDirectoryName(_dotnet)!, "shared", "Microsoft.NETCore.App"))
            .OrderBy(directory => Version.Parse(Path.GetFileName(directory).Split('-')[0]))
            .Last();
    }

    [SetUp]
    public void CreateADirectory() =>
        _directory = Directory.CreateTempSubdirectory("compiler_workers").FullName;

    [TearDown]
    public void StopTheBuildServersAndRemoveTheDirectory()
    {
        foreach (var id in _servers)
        {
            try
            {
                Process.GetProcessById(id).Kill();
            }
            catch (Exception e) when (e is ArgumentException or InvalidOperationException or Win32Exception)
            {
                // Already gone, or on its way out.
            }
        }

        _servers.Clear();

        try
        {
            Directory.Delete(_directory, recursive: true);
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
        }
    }

    [Test]
    public void ACSharpCompileIsServedByTheBuildServerWhenTheWorkerRunsOnAnotherRuntime()
    {
        // Arrange: a worker started with a DOTNET_ROOT the SDK's build server
        // cannot run on, as a worker built against an older SDK than the one
        // compiling is.
        var unusableRoot = Directory.CreateDirectory(Path.Combine(_directory, "older-dotnet")).FullName;
        var log = Path.Combine(_directory, "roslyn.log");
        var csc = CopyOfTheCSharpCompiler();
        var workingDirectory = Directory.CreateDirectory(Path.Combine(_directory, "execroot")).FullName;

        // Act
        var responses = CompileCSharpTwice(csc, workingDirectory, log, unusableRoot);

        // Assert
        Assert.That(responses.Select(response => response.ExitCode), Is.EqualTo(new[] { 0, 0 }), string.Join("\n", responses.Select(r => r.Output)));
        AssertTheBuildServerServedEveryCompile(log, compiles: 2);
    }

    [Test]
    public void ACSharpCompileIsServedByTheBuildServerWhenTheWorkingDirectoryHoldsADotnetLink()
    {
        // Arrange: an execution root links each top-level source folder, and a
        // repository may well have one called `dotnet`.
        var log = Path.Combine(_directory, "roslyn.log");
        var csc = CopyOfTheCSharpCompiler();
        var workingDirectory = Directory.CreateDirectory(Path.Combine(_directory, "execroot")).FullName;
        var sources = Directory.CreateDirectory(Path.Combine(_directory, "workspace", "dotnet")).FullName;
        var link = Path.Combine(workingDirectory, RuntimeInformation.IsOSPlatform(OSPlatform.Windows) ? "dotnet.exe" : "dotnet");
        try
        {
            Directory.CreateSymbolicLink(link, sources);
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            Assert.Ignore("Symlinks cannot be created here: " + e.Message);
        }

        // Act
        var responses = CompileCSharpTwice(csc, workingDirectory, log, dotnetRoot: null);

        // Assert
        Assert.That(responses.Select(response => response.ExitCode), Is.EqualTo(new[] { 0, 0 }), string.Join("\n", responses.Select(r => r.Output)));
        AssertTheBuildServerServedEveryCompile(log, compiles: 2);
    }

    [Test]
    public void ACSharpCompileIsServedByTheBuildServerWhereTheUsersDirectoriesAreUnusable()
    {
        // Arrange: from .NET 11 the runtime keeps the state of a named mutex in a
        // directory of the user's own, which csc and the build server need. A
        // sandbox or a remote executor can hand a worker a HOME it cannot write
        // to, and a test's TMPDIR is /tmp, which on macOS is a link the runtime
        // will not follow.
        var log = Path.Combine(_directory, "roslyn.log");
        var csc = CopyOfTheCSharpCompiler();
        var workingDirectory = Directory.CreateDirectory(Path.Combine(_directory, "execroot")).FullName;
        var temp = Path.Combine(_directory, "tmp-link");
        try
        {
            Directory.CreateSymbolicLink(temp, Directory.CreateDirectory(Path.Combine(_directory, "tmp")).FullName);
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            Assert.Ignore("Symlinks cannot be created here: " + e.Message);
        }

        // Below a file, so that it cannot be created either.
        var file = Path.Combine(_directory, "a-file");
        File.WriteAllText(file, "");
        var unusable = new Dictionary<string, string?>
        {
            ["HOME"] = Path.Combine(file, "home"),
            ["XDG_RUNTIME_DIR"] = null,
            ["TMPDIR"] = temp,
        };

        // Act
        var responses = CompileCSharpTwice(csc, workingDirectory, log, dotnetRoot: null, unusable);

        // Assert
        Assert.That(responses.Select(response => response.ExitCode), Is.EqualTo(new[] { 0, 0 }), string.Join("\n", responses.Select(r => r.Output)));
        AssertTheBuildServerServedEveryCompile(log, compiles: 2);
        if (OperatingSystem.IsLinux())
        {
            Assert.That(
                File.GetUnixFileMode(Path.Combine(temp, "rules_dotnet-" + GetEffectiveUserId())),
                Is.EqualTo(UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute));
        }
    }

    [Test]
    public void ACSharpCompileDoesNotKeepItsMutexesWhereOtherUsersCanReachThem()
    {
        if (!OperatingSystem.IsLinux())
        {
            Assert.Ignore("Only Linux gets a directory of rules_dotnet's own.");
        }

        // Arrange: the directory the worker would use, made first and open to
        // everyone, as another user could make it under a shared /tmp. Sticky, so
        // that the runtime itself would take it.
        var log = Path.Combine(_directory, "roslyn.log");
        var csc = CopyOfTheCSharpCompiler();
        var workingDirectory = Directory.CreateDirectory(Path.Combine(_directory, "execroot")).FullName;
        var temp = Directory.CreateDirectory(Path.Combine(_directory, "tmp")).FullName;
        var everyones = Path.Combine(temp, "rules_dotnet-" + GetEffectiveUserId());
        var open = UnixFileMode.StickyBit | (UnixFileMode)0x1FF;
        Directory.CreateDirectory(everyones);
        File.SetUnixFileMode(everyones, open);

        var file = Path.Combine(_directory, "a-file");
        File.WriteAllText(file, "");
        var unusable = new Dictionary<string, string?>
        {
            ["HOME"] = Path.Combine(file, "home"),
            ["XDG_RUNTIME_DIR"] = null,
            ["TMPDIR"] = temp,
        };

        // Act
        var responses = CompileCSharpTwice(csc, workingDirectory, log, dotnetRoot: null, unusable);

        // Assert: still compiled, on csc's own, and the directory left as it was.
        Assert.That(responses.Select(response => response.ExitCode), Is.EqualTo(new[] { 0, 0 }), string.Join("\n", responses.Select(r => r.Output)));
        Assert.That(Outcomes(log), Is.EqualTo(new[] { "CannotConnect", "CannotConnect" }));
        Assert.That(File.GetUnixFileMode(everyones), Is.EqualTo(open));
    }

    [DllImport("libc", EntryPoint = "geteuid")]
    private static extern uint GetEffectiveUserId();

    [Test]
    public void AnFSharpErrorRaisedDuringCodeGenerationFailsTheRequestAndTheWorkerServesTheNext(
        [Values] WorkerEncoding encoding)
    {
        // Arrange
        var failing = WriteSource("CustomMarshaler.fs", CustomMarshalerSource);
        var passing = WriteSource("Library.fs", "module Library\nlet f x = x + 1\n");
        using var worker = WorkerProcess.Start(
            _dotnet,
            new[] { _fsharpWorker, _dotnet, _fsc, "--persistent_worker" },
            _directory,
            new Dictionary<string, string?>(),
            encoding);

        // Act
        var failed = worker.Send(FSharpArguments(failing, "failing"), ResponseTimeout);
        var passed = worker.Send(FSharpArguments(passing, "passing"), ResponseTimeout);

        // Assert
        Assert.That(failed.ExitCode, Is.EqualTo(1));
        Assert.That(failed.Output, Does.Contain("error FS0980"));
        Assert.That(failed.Output, Does.Not.Contain("ReportedError"));
        Assert.That(passed.ExitCode, Is.EqualTo(0), passed.Output);
    }

    [Test]
    public void AnFSharpErrorRaisedDuringCodeGenerationFailsAPlainCompileWithItsDiagnostic()
    {
        // Arrange
        var failing = WriteSource("CustomMarshaler.fs", CustomMarshalerSource);
        var responseFile = Path.Combine(_directory, "compile.rsp");
        File.WriteAllLines(responseFile, FSharpArguments(failing, "failing"));

        // Act
        var (exitCode, output) = RunToCompletion(
            _dotnet,
            new[] { _fsharpWorker, _dotnet, _fsc, "@" + responseFile },
            _directory);

        // Assert
        Assert.That(exitCode, Is.EqualTo(1), output);
        Assert.That(output, Does.Contain("error FS0980"));
    }

    /// <summary>
    /// A P/Invoke parameter with a custom marshaller, which the F# compiler only
    /// rejects while generating IL, by raising <c>ReportedError</c>.
    /// </summary>
    private const string CustomMarshalerSource =
        "module Interop\n" +
        "open System.Runtime.InteropServices\n" +
        "[<DllImport(\"libc\")>]\n" +
        "extern int strlen([<MarshalAs(UnmanagedType.CustomMarshaler)>] string s)\n";

    /// <summary>
    /// The build server's pipe is named after the compiler's directory, so a
    /// copy of the compiler gets a server of its own rather than one some other
    /// build left running.
    /// </summary>
    private string CopyOfTheCSharpCompiler()
    {
        var source = Path.GetDirectoryName(Path.GetFullPath(_csc))!;
        var destination = Path.Combine(_directory, "roslyn");
        foreach (var file in Directory.GetFiles(source, "*", SearchOption.AllDirectories))
        {
            var target = Path.Combine(destination, Path.GetRelativePath(source, file));
            Directory.CreateDirectory(Path.GetDirectoryName(target)!);
            File.Copy(file, target);
        }

        return Path.Combine(destination, Path.GetFileName(_csc));
    }

    private List<(int ExitCode, string Output)> CompileCSharpTwice(
        string csc,
        string workingDirectory,
        string log,
        string? dotnetRoot,
        IDictionary<string, string?>? extraEnvironment = null)
    {
        var source = WriteSource("Library.cs", "public static class Library { public static int F() => 42; }\n");
        var environment = new Dictionary<string, string?>
        {
            ["RoslynCommandLineLogFile"] = log,
            ["DOTNET_HOST_PATH"] = null,
        };
        if (dotnetRoot != null)
        {
            environment["DOTNET_ROOT"] = dotnetRoot;
        }

        foreach (var (name, value) in extraEnvironment ?? new Dictionary<string, string?>())
        {
            environment[name] = value;
        }

        var responses = new List<(int, string)>();
        try
        {
            using var worker = WorkerProcess.Start(
                _dotnet,
                new[] { _csharpWorker, _dotnet, csc, "--persistent_worker" },
                workingDirectory,
                environment,
                WorkerEncoding.Json);
            for (var i = 0; i < 2; i++)
            {
                responses.Add(worker.Send(
                    new List<string>
                    {
                        "/nostdlib+",
                        "/target:library",
                        "/out:" + Quoted(Path.Combine(_directory, $"Library{i}.dll")),
                        "/r:" + Quoted(Path.Combine(_sharedFramework, "System.Runtime.dll")),
                        "/r:" + Quoted(Path.Combine(_sharedFramework, "System.Private.CoreLib.dll")),
                        Quoted(source),
                    },
                    ResponseTimeout));
            }
        }
        finally
        {
            RememberBuildServers(log);
        }

        return responses;
    }

    /// <summary>The worker hands csc its arguments in a response file, whose lines csc splits on whitespace.</summary>
    private static string Quoted(string path) => "\"" + path + "\"";

    private void RememberBuildServers(string log)
    {
        if (!File.Exists(log))
        {
            return;
        }

        foreach (Match match in Regex.Matches(ReadLog(log), @"Successfully created process with process id (\d+)"))
        {
            _servers.Add(int.Parse(match.Groups[1].Value));
        }
    }

    /// <summary>
    /// The build server holds its log open for writing for as long as it runs,
    /// and Windows only lets a reader in that shares write access.
    /// </summary>
    private static string ReadLog(string log)
    {
        using var stream = new FileStream(log, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
        using var reader = new StreamReader(stream);
        return reader.ReadToEnd();
    }

    /// <summary>
    /// csc logs how each compile went once it has its answer: <c>Completed</c>
    /// when the build server compiled it, <c>CannotConnect</c> when csc gave up
    /// waiting for the server and compiled on its own.
    /// </summary>
    private static void AssertTheBuildServerServedEveryCompile(string log, int compiles) =>
        Assert.That(Outcomes(log), Is.EqualTo(Enumerable.Repeat("Completed", compiles).ToArray()));

    private static List<string> Outcomes(string log) =>
        Regex.Matches(ReadLog(log), @"Server compilation completed: (\w+)")
            .Select(match => match.Groups[1].Value)
            .ToList();

    private string WriteSource(string name, string contents)
    {
        var path = Path.Combine(_directory, name);
        File.WriteAllText(path, contents);
        return path;
    }

    private List<string> FSharpArguments(string source, string name)
    {
        var arguments = new List<string>
        {
            "--noframework",
            "--nocopyfsharpcore",
            "--target:library",
            "--out:" + Path.Combine(_directory, name + ".dll"),
            "-r:" + Path.Combine(Path.GetDirectoryName(Path.GetFullPath(_fsc))!, "FSharp.Core.dll"),
        };

        foreach (var assembly in Directory.GetFiles(_sharedFramework, "*.dll").Where(IsManaged))
        {
            arguments.Add("-r:" + assembly);
        }

        arguments.Add(source);
        return arguments;
    }

    private static bool IsManaged(string path)
    {
        using var stream = File.OpenRead(path);
        using var pe = new PEReader(stream);
        try
        {
            return pe.HasMetadata;
        }
        catch (BadImageFormatException)
        {
            return false;
        }
    }

    private static (int ExitCode, string Output) RunToCompletion(string fileName, IEnumerable<string> arguments, string workingDirectory)
    {
        var startInfo = new ProcessStartInfo(fileName)
        {
            WorkingDirectory = workingDirectory,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
        };
        foreach (var argument in arguments)
        {
            startInfo.ArgumentList.Add(argument);
        }

        using var process = Process.Start(startInfo)!;
        var standardOutput = process.StandardOutput.ReadToEndAsync();
        var standardError = process.StandardError.ReadToEndAsync();
        if (!process.WaitForExit(ResponseTimeout))
        {
            process.Kill(entireProcessTree: true);
            Assert.Fail("the worker did not finish");
        }

        return (process.ExitCode, standardOutput.Result + standardError.Result);
    }

    /// <summary>A worker serving requests over its standard input and output, in one of the protocol's encodings.</summary>
    private sealed class WorkerProcess : IDisposable
    {
        private readonly Process _process;
        private readonly WorkerEncoding _encoding;
        private readonly Task<string> _standardError;
        private readonly List<byte> _pending = new();
        private int _requestId;

        private WorkerProcess(Process process, WorkerEncoding encoding)
        {
            _process = process;
            _encoding = encoding;
            _standardError = process.StandardError.ReadToEndAsync();
        }

        public static WorkerProcess Start(
            string fileName,
            IEnumerable<string> arguments,
            string workingDirectory,
            IDictionary<string, string?> environment,
            WorkerEncoding encoding)
        {
            var startInfo = new ProcessStartInfo(fileName)
            {
                WorkingDirectory = workingDirectory,
                RedirectStandardInput = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
            };
            foreach (var argument in arguments)
            {
                startInfo.ArgumentList.Add(argument);
            }

            foreach (var (name, value) in environment)
            {
                if (value == null)
                {
                    startInfo.Environment.Remove(name);
                }
                else
                {
                    startInfo.Environment[name] = value;
                }
            }

            return new WorkerProcess(Process.Start(startInfo)!, encoding);
        }

        public (int ExitCode, string Output) Send(IReadOnlyList<string> arguments, TimeSpan timeout)
        {
            var id = ++_requestId;
            var request = WorkerProtocol.Request(_encoding, id, arguments);
            _process.StandardInput.BaseStream.Write(request);
            _process.StandardInput.BaseStream.Flush();

            var stdout = _process.StandardOutput.BaseStream;
            var buffer = new byte[8192];
            var deadline = DateTime.UtcNow + timeout;
            while (true)
            {
                if (WorkerProtocol.TryTakeResponse(_encoding, _pending, out var response))
                {
                    Assert.That(response.RequestId, Is.EqualTo(id));
                    return (response.ExitCode, response.Output);
                }

                var read = stdout.ReadAsync(buffer, 0, buffer.Length);
                if (!read.Wait(deadline - DateTime.UtcNow) || read.Result == 0)
                {
                    Assert.Fail("no response from the worker: " + Describe());
                }

                _pending.AddRange(buffer.Take(read.Result));
            }
        }

        private string Describe()
        {
            if (!_process.HasExited)
            {
                return "it is still running";
            }

            return $"it exited with {_process.ExitCode}: {_standardError.Result}";
        }

        public void Dispose()
        {
            _process.StandardInput.Close();
            if (!_process.WaitForExit(TimeSpan.FromSeconds(30)))
            {
                _process.Kill(entireProcessTree: true);
            }

            _process.Dispose();
        }
    }
}
