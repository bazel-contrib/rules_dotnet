var values = new List<string> { Path.GetFileName("dir/item.txt") };
if (values.Single() != "item.txt")
{
    throw new InvalidOperationException("Unexpected value");
}
await Task.CompletedTask;
