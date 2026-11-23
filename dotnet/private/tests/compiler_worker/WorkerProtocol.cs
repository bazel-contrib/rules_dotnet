#nullable enable

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace RulesDotnet.Tests;

/// <summary>The two encodings of Bazel's worker protocol.</summary>
public enum WorkerEncoding
{
    Json,
    Protobuf,
}

/// <summary>A WorkResponse, as Bazel reads it back.</summary>
public readonly record struct WorkResponse(int RequestId, int ExitCode, string Output);

/// <summary>
/// Bazel's side of the worker protocol, which writes the requests and reads the
/// responses: https://github.com/bazelbuild/bazel/blob/master/src/main/protobuf/worker_protocol.proto
/// Written apart from the worker's own, so that a mistake there is not
/// mirrored here.
/// </summary>
public static class WorkerProtocol
{
    /// <summary>
    /// A work request the way Bazel writes it, with an <c>Input</c> and its
    /// digest for each of <paramref name="inputs"/>. <paramref name="extraFields"/>,
    /// already encoded, go at the end of a protobuf request.
    /// </summary>
    public static byte[] Request(
        WorkerEncoding encoding,
        int requestId,
        IReadOnlyList<string> arguments,
        IReadOnlyList<string>? inputs = null,
        byte[]? extraFields = null)
    {
        inputs ??= Array.Empty<string>();
        if (encoding == WorkerEncoding.Json)
        {
            return JsonSerializer.SerializeToUtf8Bytes(new
            {
                arguments,
                inputs = inputs.Select(path => new { path, digest = Convert.ToBase64String(Digest(path)) }),
                requestId,
            });
        }

        var message = new List<byte>();
        foreach (var argument in arguments)
        {
            WriteLengthDelimited(message, 1, Encoding.UTF8.GetBytes(argument));
        }

        foreach (var path in inputs)
        {
            var input = new List<byte>();
            WriteLengthDelimited(input, 1, Encoding.UTF8.GetBytes(path));
            WriteLengthDelimited(input, 2, Digest(path));
            WriteLengthDelimited(message, 2, input.ToArray());
        }

        // proto3 leaves a field at its default value out.
        if (requestId != 0)
        {
            WriteVarint(message, 3 << 3 | 0);
            WriteVarint(message, unchecked((ulong)(long)requestId));
        }

        message.AddRange(extraFields ?? Array.Empty<byte>());

        var delimited = new List<byte>();
        WriteVarint(delimited, (ulong)message.Count);
        delimited.AddRange(message);
        return delimited.ToArray();
    }

    /// <summary>Every response in <paramref name="bytes"/>, which must hold nothing else.</summary>
    public static List<WorkResponse> Responses(WorkerEncoding encoding, byte[] bytes)
    {
        var pending = new List<byte>(bytes);
        var responses = new List<WorkResponse>();
        while (TryTakeResponse(encoding, pending, out var response))
        {
            responses.Add(response);
        }

        if (pending.Count > 0)
        {
            throw new InvalidDataException($"{pending.Count} bytes after the last response");
        }

        return responses;
    }

    /// <summary>Takes a response off the front of <paramref name="pending"/>, or returns false while it is incomplete.</summary>
    public static bool TryTakeResponse(WorkerEncoding encoding, List<byte> pending, out WorkResponse response)
    {
        return encoding == WorkerEncoding.Json
            ? TryTakeJsonResponse(pending, out response)
            : TryTakeProtobufResponse(pending, out response);
    }

    public static void WriteVarint(List<byte> bytes, ulong value)
    {
        while (value >= 0x80)
        {
            bytes.Add((byte)(value | 0x80));
            value >>= 7;
        }

        bytes.Add((byte)value);
    }

    public static void WriteLengthDelimited(List<byte> bytes, int field, byte[] value)
    {
        WriteVarint(bytes, (ulong)(field << 3 | 2));
        WriteVarint(bytes, (ulong)value.Length);
        bytes.AddRange(value);
    }

    private static byte[] Digest(string path) => SHA256.HashData(Encoding.UTF8.GetBytes(path));

    private static bool TryTakeJsonResponse(List<byte> pending, out WorkResponse response)
    {
        var reader = new Utf8JsonReader(pending.ToArray(), isFinalBlock: false, state: default);
        if (!JsonDocument.TryParseValue(ref reader, out var document))
        {
            response = default;
            return false;
        }

        using (document)
        {
            var root = document.RootElement;
            int Number(string name) => root.TryGetProperty(name, out var value) ? value.GetInt32() : 0;
            response = new WorkResponse(
                Number("requestId"),
                Number("exitCode"),
                root.TryGetProperty("output", out var output) ? output.GetString() ?? "" : "");
        }

        pending.RemoveRange(0, (int)reader.BytesConsumed);
        return true;
    }

    private static bool TryTakeProtobufResponse(List<byte> pending, out WorkResponse response)
    {
        var bytes = pending.ToArray();
        var position = 0;
        if (!TryReadVarint(bytes, ref position, out var length) || (ulong)(bytes.Length - position) < length)
        {
            response = default;
            return false;
        }

        var end = position + (int)length;
        var requestId = 0;
        var exitCode = 0;
        var output = "";
        while (position < end)
        {
            var tag = ReadVarint(bytes, ref position);
            switch (tag)
            {
                case 1 << 3 | 0:
                    exitCode = unchecked((int)ReadVarint(bytes, ref position));
                    break;
                case 2 << 3 | 2:
                    var size = (int)ReadVarint(bytes, ref position);
                    output = Encoding.UTF8.GetString(bytes, position, size);
                    position += size;
                    break;
                case 3 << 3 | 0:
                    requestId = unchecked((int)ReadVarint(bytes, ref position));
                    break;
                default:
                    throw new InvalidDataException($"a WorkResponse has no tag {tag}");
            }
        }

        if (position != end)
        {
            throw new InvalidDataException("a field runs past the end of the WorkResponse");
        }

        pending.RemoveRange(0, end);
        response = new WorkResponse(requestId, exitCode, output);
        return true;
    }

    private static ulong ReadVarint(byte[] bytes, ref int position) =>
        TryReadVarint(bytes, ref position, out var value)
            ? value
            : throw new InvalidDataException("a WorkResponse ends partway through a varint");

    private static bool TryReadVarint(byte[] bytes, ref int position, out ulong value)
    {
        value = 0;
        for (var shift = 0; position < bytes.Length; shift += 7)
        {
            var b = bytes[position++];
            value |= (ulong)(b & 0x7F) << shift;
            if (b < 0x80)
            {
                return true;
            }
        }

        return false;
    }
}
