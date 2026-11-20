using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Text.Json;
using NUnit.Framework;

namespace RulesDotnet.Tests;

[TestFixture]
public class WorkerLoopTest
{
    private static byte[] JsonRequests(params string[][] requests)
    {
        var bytes = new List<byte>();
        for (var id = 0; id < requests.Length; id++)
        {
            // Back to back, with nothing between them, the way Bazel writes them.
            bytes.AddRange(JsonSerializer.SerializeToUtf8Bytes(new { arguments = requests[id], requestId = id }));
        }

        return bytes.ToArray();
    }

    private static List<JsonElement> Responses(MemoryStream stdout)
    {
        var responses = new List<JsonElement>();
        var bytes = stdout.ToArray();
        var offset = 0;
        while (offset < bytes.Length)
        {
            var reader = new Utf8JsonReader(bytes.AsSpan(offset), isFinalBlock: false, state: default);
            using var document = JsonDocument.ParseValue(ref reader);
            responses.Add(document.RootElement.Clone());
            offset += (int)reader.BytesConsumed;
        }

        return responses;
    }

    /// <summary>A WorkRequest as Bazel's proto protocol writes it: varint length, then the message.</summary>
    private static byte[] ProtobufRequest(params string[] arguments)
    {
        var message = new List<byte>();
        foreach (var argument in arguments)
        {
            // Field 1, `repeated string arguments`, length delimited.
            message.Add(0x0A);
            WriteVarint(message, Encoding.UTF8.GetByteCount(argument));
            message.AddRange(Encoding.UTF8.GetBytes(argument));
        }

        var delimited = new List<byte>();
        WriteVarint(delimited, message.Count);
        delimited.AddRange(message);
        return delimited.ToArray();
    }

    private static void WriteVarint(List<byte> bytes, int value)
    {
        while (value >= 0x80)
        {
            bytes.Add((byte)(value | 0x80));
            value >>= 7;
        }

        bytes.Add((byte)value);
    }

    [Test]
    public void EachRequestIsAnsweredAndAThrowingOneDoesNotEndTheWorker()
    {
        // Arrange
        var stdin = new MemoryStream(JsonRequests(new[] { "throw" }, new[] { "Library.fs" }));
        var stdout = new MemoryStream();
        var errors = new StringWriter();

        // Act
        var exitCode = Worker.RunWorkerLoop(
            (arguments, output) =>
            {
                if (arguments[0] == "throw")
                {
                    output.AppendLine("Library.fs(1,1): error FS0980: the diagnostic");
                    throw new InvalidOperationException("the compiler gave up");
                }

                return 0;
            },
            stdin,
            stdout,
            errors);

        // Assert
        var responses = Responses(stdout);
        Assert.That(exitCode, Is.EqualTo(0));
        Assert.That(responses, Has.Count.EqualTo(2));
        Assert.That(responses[0].GetProperty("requestId").GetInt32(), Is.EqualTo(0));
        Assert.That(responses[0].GetProperty("exitCode").GetInt32(), Is.EqualTo(1));
        Assert.That(responses[0].GetProperty("output").GetString(), Does.Contain("error FS0980: the diagnostic"));
        Assert.That(responses[1].GetProperty("requestId").GetInt32(), Is.EqualTo(1));
        Assert.That(responses[1].GetProperty("exitCode").GetInt32(), Is.EqualTo(0));
    }

    [Test]
    public void AProtobufRequestFailsTheWorkerWithAMessageNamingTheJsonProtocol()
    {
        // Arrange
        var arguments = new List<string> { "/unsafe-", "/checked-", "/nostdlib+" };
        for (var i = 0; i < 20; i++)
        {
            arguments.Add("-r:external/dotnet/packs/Microsoft.NETCore.App.Ref/ref/net10.0/System.Runtime.dll");
        }

        var stdin = new MemoryStream(ProtobufRequest(arguments.ToArray()));
        var stdout = new MemoryStream();
        var errors = new StringWriter();
        var compiled = false;

        // Act
        var exitCode = Worker.RunWorkerLoop(
            (_, _) =>
            {
                compiled = true;
                return 0;
            },
            stdin,
            stdout,
            errors);

        // Assert
        Assert.That(exitCode, Is.EqualTo(1));
        Assert.That(compiled, Is.False);
        Assert.That(stdout.Length, Is.EqualTo(0));
        Assert.That(errors.ToString(), Does.Contain("JSON worker protocol"));
        Assert.That(errors.ToString(), Does.Contain("persistentWorkerProtocol=json"));
    }

    [Test]
    public void ANullRequestFailsTheWorkerInsteadOfEndingIt()
    {
        // Arrange
        var stdin = new MemoryStream(Encoding.UTF8.GetBytes("null"));
        var errors = new StringWriter();

        // Act
        var exitCode = Worker.RunWorkerLoop((_, _) => 0, stdin, new MemoryStream(), errors);

        // Assert
        Assert.That(exitCode, Is.EqualTo(1));
        Assert.That(errors.ToString(), Does.Contain("JSON worker protocol"));
    }
}
