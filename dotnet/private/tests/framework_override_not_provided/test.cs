using NUnit.Framework;
using System;
using System.Security.Cryptography.Xml;

[TestFixture]
public sealed class LibTests
{
    [Test]
    public void LibCompilesAndValueIsNotNull()
    {
        Assert.IsNotNull(new KeyInfoName().GetXml().OuterXml);
    }
}

