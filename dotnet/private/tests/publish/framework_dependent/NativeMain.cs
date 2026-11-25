using System;
using System.Runtime.InteropServices;

namespace NativeOnly
{
    // Loads a native library built in this workspace and no other native
    // library, so that nothing but where the publish puts it decides whether
    // the host finds it.
    public static class Program
    {
        [DllImport("native")]
        private static extern int return42();

        public static void Main()
        {
            if (return42() != 42)
            {
                throw new Exception("First party native call should have returned 42");
            }

            Console.WriteLine("First party native call returned 42");
        }
    }
}
