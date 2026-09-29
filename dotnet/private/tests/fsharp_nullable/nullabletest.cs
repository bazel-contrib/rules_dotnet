using System.Reflection;
using Lib;
using NUnit.Framework;

// NullabilityInfoContext reads the same metadata the C# compiler does, so these
// assert what a C# consumer of the F# library sees.
[TestFixture]
public sealed class NullableInteropTests
{
    private static readonly NullabilityInfoContext Context = new();

    [Test]
    public void NullableReturnIsNullableInCSharp()
    {
        var method = typeof(NullableEntity).GetMethod(nameof(NullableEntity.TryFind))!;
        Assert.AreEqual(NullabilityState.Nullable, Context.Create(method.ReturnParameter).ReadState);
    }

    [Test]
    public void PlainParameterIsNotNullInCSharp()
    {
        var parameter = typeof(NullableEntity).GetMethod(nameof(NullableEntity.Length))!.GetParameters()[0];
        Assert.AreEqual(NullabilityState.NotNull, Context.Create(parameter).WriteState);
    }

    [Test]
    public void NullableIsDefined()
    {
        Assert.IsTrue(NullableEntity.DefinesNullable);
    }

    [Test]
    public void NullableReturnCanBeNull()
    {
        Assert.IsNull(NullableEntity.TryFind("absent"));
        Assert.AreEqual("value", NullableEntity.TryFind("present"));
    }
}
