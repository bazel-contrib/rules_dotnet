#nullable enable

using System;
using System.Collections.Generic;
using System.Text;
using RulesDotnet;

namespace CSharpCompilerWorker
{
    /// <summary>
    /// Runs the Roslyn command line compiler: as a Bazel persistent worker when
    /// Bazel passes <c>--persistent_worker</c>, and as a single compilation
    /// otherwise, so that turning the worker strategy off is always safe.
    ///
    /// Living across compilations is what lets Roslyn's build server be reused,
    /// which is where nearly all of the time of a small compilation goes.
    /// </summary>
    public static class Program
    {
        public static int Main(string[] args)
        {
            // <dotnet> <csc.dll> [--persistent_worker] [args...]
            if (args.Length < 2)
            {
                Console.Error.WriteLine("usage: csharp_compiler_worker <dotnet> <csc.dll> [flags...] [args...]");
                return 1;
            }

            var dotnet = args[0];
            var compiler = args[1];
            var rest = new List<string>(args[2..]);
            var persistent = Worker.TakeFlag(rest, "--persistent_worker");

            // Reuse Roslyn's build server between compilations, but do not let it
            // outlive the build by much: Bazel kills the worker, and the server is
            // the worker's own child.
            var flags = persistent ? new[] { "/shared", "/keepalive:60" } : Array.Empty<string>();

            int Compile(List<string> arguments, StringBuilder output)
            {
                var resolved = Worker.ResolveInputLinks(
                    arguments,
                    "-r:",
                    "/r:",
                    "-reference:",
                    "/reference:",
                    "-a:",
                    "/a:",
                    "-analyzer:",
                    "/analyzer:");
                return Worker.RunCompiler(dotnet, compiler, flags, resolved, "-pathmap:", output);
            }

            return persistent ? Worker.RunWorkerLoop(Compile) : Worker.RunOnce(Compile, rest);
        }
    }
}
