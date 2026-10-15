using System;
using Calculator;

namespace CalculatorApp;

public static class Program
{
    public static string Run() => Arithmetic.ResultToJson(Arithmetic.Add(2, 3));

    public static void Main(string[] args)
    {
        Console.WriteLine(Run());
    }
}
