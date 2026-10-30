internal static class XunitShim {
	public static int Main(string[] args) => Xunit.Runner.InProc.SystemConsole.ConsoleRunner.Run(args).GetAwaiter().GetResult();
}
