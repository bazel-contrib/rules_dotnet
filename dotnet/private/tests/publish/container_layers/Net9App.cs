namespace Net9App
{
    public static class Program
    {
        public static void Main()
        {
            System.Console.WriteLine(Bazel.Runfiles.Create() != null);
        }
    }
}
