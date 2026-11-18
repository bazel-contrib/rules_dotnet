using System;

class Test
{
    static int Main(string[] args)
    {
        string[] expected = { "--output=D:\\temp\\out", "a\\b", "a b", "x ^ y", "a\"b" };
        if (args.Length != expected.Length)
        {
            Console.Error.WriteLine("expected " + expected.Length + " arguments, got " + args.Length);
            return 1;
        }
        for (int i = 0; i < expected.Length; i++)
        {
            if (args[i] != expected[i])
            {
                Console.Error.WriteLine("expected '" + expected[i] + "', got '" + args[i] + "'");
                return 1;
            }
        }
        return 0;
    }
}
