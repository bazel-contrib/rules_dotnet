using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using NUnit.Framework;

namespace RulesDotnet.Tests;

[TestFixture]
public class WorkerLoopTest
{
    /// <summary>
    /// Enough references to take a request past a two-byte length and across
    /// more than one read, the way a targeting pack does.
    /// </summary>
    private static readonly string[] ManyReferences = Enumerable
        .Range(0, 300)
        .Select(i => $"-r:external/dotnet/packs/Microsoft.NETCore.App.Ref/ref/net10.0/System.Assembly{i}.dll")
        .ToArray();

    /// <summary>The requests back to back, numbered from 0, with an input each.</summary>
    private static byte[] Requests(WorkerEncoding encoding, params string[][] requests) =>
        requests
            .SelectMany((arguments, id) => WorkerProtocol.Request(encoding, id, arguments, inputs: new[] { "src/Library.cs" }))
            .ToArray();

    [TestCase(WorkerEncoding.Json)]
    [TestCase(WorkerEncoding.Protobuf)]
    public void EachRequestIsAnsweredInItsEncodingAndAThrowingOneDoesNotEndTheWorker(WorkerEncoding encoding)
    {
        // Arrange
        var requests = new[]
        {
            new[] { "throw" },
            new[] { "/unsafe-", "/checked-" }.Concat(ManyReferences).Append("Bibliothèque.cs").ToArray(),
        };
        var stdin = new MemoryStream(Requests(encoding, requests));
        var stdout = new MemoryStream();
        var received = new List<List<string>>();

        // Act
        var exitCode = Worker.RunWorkerLoop(
            (arguments, output) =>
            {
                received.Add(arguments);
                if (arguments[0] == "throw")
                {
                    output.AppendLine("Library.fs(1,1): error FS0980: the diagnostic");
                    throw new InvalidOperationException("the compiler gave up");
                }

                return 0;
            },
            stdin,
            stdout,
            new StringWriter());

        // Assert
        var responses = WorkerProtocol.Responses(encoding, stdout.ToArray());
        Assert.That(exitCode, Is.EqualTo(0));
        Assert.That(received, Is.EqualTo(requests));
        Assert.That(responses, Has.Count.EqualTo(2));
        Assert.That(responses[0].RequestId, Is.EqualTo(0));
        Assert.That(responses[0].ExitCode, Is.EqualTo(1));
        Assert.That(responses[0].Output, Does.Contain("error FS0980: the diagnostic"));
        Assert.That(responses[1], Is.EqualTo(new WorkResponse(RequestId: 1, ExitCode: 0, Output: "")));
    }

    [TestCase(WorkerEncoding.Json)]
    [TestCase(WorkerEncoding.Protobuf)]
    public void RequestsArrivingOneByteAtATimeAreEachAnswered(WorkerEncoding encoding)
    {
        // Arrange
        var stdin = new TrickleStream(Requests(encoding, new[] { "A.cs" }, new[] { "B.cs" }));
        var stdout = new MemoryStream();
        var received = new List<List<string>>();

        // Act
        var exitCode = Worker.RunWorkerLoop(
            (arguments, _) =>
            {
                received.Add(arguments);
                return 0;
            },
            stdin,
            stdout,
            new StringWriter());

        // Assert
        Assert.That(exitCode, Is.EqualTo(0));
        Assert.That(received, Is.EqualTo(new[] { new[] { "A.cs" }, new[] { "B.cs" } }));
        Assert.That(
            WorkerProtocol.Responses(encoding, stdout.ToArray()).Select(response => response.RequestId),
            Is.EqualTo(new[] { 0, 1 }));
    }

    [Test]
    public void TheFieldsOfAProtobufRequestTheWorkerDoesNotUseAreSkipped()
    {
        // Arrange: verbosity and sandbox_dir, then a field of each wire type a
        // later version of the protocol could add.
        var extraFields = new List<byte>();
        WorkerProtocol.WriteVarint(extraFields, 5 << 3 | 0);
        WorkerProtocol.WriteVarint(extraFields, 10);
        WorkerProtocol.WriteLengthDelimited(extraFields, 6, Encoding.UTF8.GetBytes("sandbox/1"));
        WorkerProtocol.WriteVarint(extraFields, 100 << 3 | 0);
        WorkerProtocol.WriteVarint(extraFields, ulong.MaxValue);
        WorkerProtocol.WriteVarint(extraFields, 101 << 3 | 1);
        extraFields.AddRange(new byte[8]);
        WorkerProtocol.WriteLengthDelimited(extraFields, 102, new byte[] { 0x0A, 0x01, 0x78 });
        WorkerProtocol.WriteVarint(extraFields, 103 << 3 | 5);
        extraFields.AddRange(new byte[4]);
        var request = WorkerProtocol.Request(
            WorkerEncoding.Protobuf,
            requestId: 7,
            new[] { "/target:library", "Library.cs" },
            inputs: new[] { "Library.cs", "external/dotnet/System.Runtime.dll" },
            extraFields: extraFields.ToArray());
        var stdout = new MemoryStream();
        var received = new List<List<string>>();

        // Act
        var exitCode = Worker.RunWorkerLoop(
            (arguments, _) =>
            {
                received.Add(arguments);
                return 0;
            },
            new MemoryStream(request),
            stdout,
            new StringWriter());

        // Assert
        Assert.That(exitCode, Is.EqualTo(0));
        Assert.That(received, Is.EqualTo(new[] { new[] { "/target:library", "Library.cs" } }));
        Assert.That(
            WorkerProtocol.Responses(WorkerEncoding.Protobuf, stdout.ToArray()),
            Is.EqualTo(new[] { new WorkResponse(RequestId: 7, ExitCode: 0, Output: "") }));
    }

    [TestCase(WorkerEncoding.Json)]
    [TestCase(WorkerEncoding.Protobuf)]
    public void ANegativeExitCodeAndALargeRequestIdReachBazelIntact(WorkerEncoding encoding)
    {
        // Arrange: the access violation a crashing compiler exits with on Windows.
        const int accessViolation = unchecked((int)0xC0000005);
        var request = WorkerProtocol.Request(encoding, requestId: int.MaxValue, new[] { "Library.cs" });
        var stdout = new MemoryStream();

        // Act
        var exitCode = Worker.RunWorkerLoop(
            (_, output) =>
            {
                output.Append("crashed");
                return accessViolation;
            },
            new MemoryStream(request),
            stdout,
            new StringWriter());

        // Assert
        Assert.That(exitCode, Is.EqualTo(0));
        Assert.That(
            WorkerProtocol.Responses(encoding, stdout.ToArray()),
            Is.EqualTo(new[] { new WorkResponse(RequestId: int.MaxValue, ExitCode: accessViolation, Output: "crashed") }));
    }

    [Test]
    public void JsonRequestsEachOnALineOfTheirOwnAreEachAnswered()
    {
        // Arrange: newline-delimited, with a line break after the last one too.
        string Line(int id, string source) =>
            Encoding.UTF8.GetString(WorkerProtocol.Request(WorkerEncoding.Json, id, new[] { source }));
        var stdin = new MemoryStream(Encoding.UTF8.GetBytes(Line(0, "A.cs") + "\r\n" + Line(1, "B.cs") + "\n"));
        var stdout = new MemoryStream();

        // Act
        var exitCode = Worker.RunWorkerLoop((_, _) => 0, stdin, stdout, new StringWriter());

        // Assert
        Assert.That(exitCode, Is.EqualTo(0));
        Assert.That(
            WorkerProtocol.Responses(WorkerEncoding.Json, stdout.ToArray()).Select(response => response.RequestId),
            Is.EqualTo(new[] { 0, 1 }));
    }

    [Test]
    public void ANullJsonRequestFailsTheWorkerInsteadOfEndingIt()
    {
        // Arrange
        var stdin = new MemoryStream(
            WorkerProtocol.Request(WorkerEncoding.Json, 0, new[] { "Library.cs" })
                .Concat(Encoding.UTF8.GetBytes("null"))
                .ToArray());
        var stdout = new MemoryStream();
        var errors = new StringWriter();

        // Act
        var exitCode = Worker.RunWorkerLoop((_, _) => 0, stdin, stdout, errors);

        // Assert
        Assert.That(exitCode, Is.EqualTo(1));
        Assert.That(WorkerProtocol.Responses(WorkerEncoding.Json, stdout.ToArray()), Has.Count.EqualTo(1));
        Assert.That(errors.ToString(), Does.Contain("could not read a JSON work request"));
    }

    [TestCase(WorkerEncoding.Json, "JSON")]
    [TestCase(WorkerEncoding.Protobuf, "protobuf")]
    public void ARequestCutShortFailsTheWorkerInsteadOfEndingIt(WorkerEncoding encoding, string name)
    {
        // Arrange
        var request = WorkerProtocol.Request(encoding, 0, new[] { "/target:library", "Library.cs" });
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
            new MemoryStream(request[..^3]),
            stdout,
            errors);

        // Assert
        Assert.That(exitCode, Is.EqualTo(1));
        Assert.That(compiled, Is.False);
        Assert.That(stdout.Length, Is.EqualTo(0));
        Assert.That(errors.ToString(), Does.Contain($"could not read a {name} work request"));
        Assert.That(errors.ToString(), Does.Contain("ended partway through a work request"));
    }

    /// <summary>Hands out its bytes one at a time, as a pipe may.</summary>
    private sealed class TrickleStream : Stream
    {
        private readonly MemoryStream _bytes;

        public TrickleStream(byte[] bytes) => _bytes = new MemoryStream(bytes);

        public override bool CanRead => true;

        public override bool CanSeek => false;

        public override bool CanWrite => false;

        public override long Length => throw new NotSupportedException();

        public override long Position
        {
            get => throw new NotSupportedException();
            set => throw new NotSupportedException();
        }

        public override int Read(byte[] buffer, int offset, int count) =>
            _bytes.Read(buffer, offset, Math.Min(count, 1));

        public override int Read(Span<byte> buffer) =>
            _bytes.Read(buffer[..Math.Min(buffer.Length, 1)]);

        public override void Flush()
        {
        }

        public override long Seek(long offset, SeekOrigin origin) => throw new NotSupportedException();

        public override void SetLength(long value) => throw new NotSupportedException();

        public override void Write(byte[] buffer, int offset, int count) => throw new NotSupportedException();
    }
}
