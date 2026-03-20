using System;
using System.System.Security.Cryptography.Xml

namespace Lib
{
    public static class Program
    {
        public static String GetValue()
        {
            System.Security.Cryptography.Xml.EncryptedXml e = new System.Security.Cryptography.Xml.EncryptedXml();
            return e.GetXml().OuterXml;
        }
    }
}