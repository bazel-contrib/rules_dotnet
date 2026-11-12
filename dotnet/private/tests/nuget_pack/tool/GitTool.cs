using System;
using System.IO;
using LibGit2Sharp;

/// <summary>A tool that calls into libgit2, the native library of whichever runtime it runs on.</summary>
public static class GitTool
{
    public static int Main(string[] args)
    {
        var path = Path.Combine(Path.GetTempPath(), "git-tool-" + Guid.NewGuid().ToString("N"));
        try
        {
            using var repository = new Repository(path);
            Console.WriteLine($"{path} is a repository");
            return 1;
        }
        catch (RepositoryNotFoundException)
        {
            Console.WriteLine($"Hello {string.Join(" ", args)}: libgit2 found no repository");
            return 0;
        }
    }
}
