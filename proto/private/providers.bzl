"Providers for C# proto rules."

CsharpProtoCompilerInfo = provider(
    doc = "Information needed to generate C# code from protos.",
    fields = {
        "proto_lang_toolchain_info": "ProtoLangToolchainInfo: protoc invocation details for this C# proto compiler.",
    },
)

CsharpProtoSourceInfo = provider(
    doc = "Generated C# source trees produced from proto_library targets.",
    fields = {
        "generated_source_dirs": "list[File]: Directories containing generated C# sources.",
    },
)
