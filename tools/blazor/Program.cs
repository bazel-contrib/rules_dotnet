using System.CommandLine;

var mainCmd = new RootCommand("Blazor files and assets helper for rules_dotnet");

Bazel.PreprocessCmd.Init(mainCmd);
Bazel.PublishCmd.Init(mainCmd);

return await mainCmd.Parse(args).InvokeAsync();
