using System;
using System.Security.Cryptography.Xml;

namespace Lib
{
    public static class Program
    {
        public static String GetValue()
        {
            // It doesn't matter what we do here.  It just needs to compile.
            return new KeyInfoName().GetXml().OuterXml;
        }
    }
}