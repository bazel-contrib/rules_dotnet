"Public API for C# proto rules."

load(
    "//proto/private:compiler.bzl",
    _csharp_grpc_proto_compiler = "csharp_grpc_proto_compiler",
    _csharp_proto_compiler = "csharp_proto_compiler",
    _grpc_csharp_plugin = "grpc_csharp_plugin",
)
load("//proto/private:library.bzl", _csharp_proto_library = "csharp_proto_library")
load("//proto/private:providers.bzl", _CsharpProtoCompilerInfo = "CsharpProtoCompilerInfo")

csharp_proto_compiler = _csharp_proto_compiler
csharp_grpc_proto_compiler = _csharp_grpc_proto_compiler
csharp_proto_library = _csharp_proto_library
grpc_csharp_plugin = _grpc_csharp_plugin
CsharpProtoCompilerInfo = _CsharpProtoCompilerInfo
