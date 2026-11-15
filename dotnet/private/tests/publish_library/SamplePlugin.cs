namespace RulesDotnet.Tests.PublishLibrary;

public sealed class SamplePlugin : IPlugin
{
    public string Execute(string input)
    {
        return $"Plugin({ContractBase.Prefix(input)}, PrivateDep:{PrivateDep.Answer()})";
    }
}
