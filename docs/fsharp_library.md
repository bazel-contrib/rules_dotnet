<!-- Generated with Stardoc: http://skydoc.bazel.build -->

Rule for compiling F# libraries.

<a id="fsharp_library"></a>

## fsharp_library

<pre>
load("@rules_dotnet//dotnet/private/rules/fsharp:library.bzl", "fsharp_library")

fsharp_library(<a href="#fsharp_library-name">name</a>, <a href="#fsharp_library-deps">deps</a>, <a href="#fsharp_library-srcs">srcs</a>, <a href="#fsharp_library-data">data</a>, <a href="#fsharp_library-resources">resources</a>, <a href="#fsharp_library-out">out</a>, <a href="#fsharp_library-compile_data">compile_data</a>, <a href="#fsharp_library-compiler_options">compiler_options</a>, <a href="#fsharp_library-defines">defines</a>,
               <a href="#fsharp_library-exports">exports</a>, <a href="#fsharp_library-generate_documentation_file">generate_documentation_file</a>, <a href="#fsharp_library-internals_visible_to">internals_visible_to</a>, <a href="#fsharp_library-keyfile">keyfile</a>, <a href="#fsharp_library-langversion">langversion</a>,
               <a href="#fsharp_library-nowarn">nowarn</a>, <a href="#fsharp_library-project_sdk">project_sdk</a>, <a href="#fsharp_library-target_frameworks">target_frameworks</a>, <a href="#fsharp_library-treat_warnings_as_errors">treat_warnings_as_errors</a>, <a href="#fsharp_library-warning_level">warning_level</a>,
               <a href="#fsharp_library-warnings_as_errors">warnings_as_errors</a>, <a href="#fsharp_library-warnings_not_as_errors">warnings_not_as_errors</a>)
</pre>

Compile a F# DLL

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="fsharp_library-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="fsharp_library-deps"></a>deps |  Other libraries, binaries, or imported DLLs   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="fsharp_library-srcs"></a>srcs |  The source files used in the compilation.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="fsharp_library-data"></a>data |  Runtime files. It is recommended to use the @rules_dotnet//tools/runfiles library to read the runtime files.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="fsharp_library-resources"></a>resources |  A list of files to embed in the DLL as resources.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="fsharp_library-out"></a>out |  File name, without extension, of the built assembly.   | String | optional |  `""`  |
| <a id="fsharp_library-compile_data"></a>compile_data |  Additional compile time files.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="fsharp_library-compiler_options"></a>compiler_options |  Additional options to pass to the compiler. This attribute should only be used if the compiler flag has not already been exposed as an attribute.   | List of strings | optional |  `[]`  |
| <a id="fsharp_library-defines"></a>defines |  A list of preprocessor directive symbols to define.   | List of strings | optional |  `[]`  |
| <a id="fsharp_library-exports"></a>exports |  List of targets to add to the dependencies of those that depend on this target. Use this sparingly as it weakens the precision of the build graph.<br><br>This attribute does nothing if you don't have strict dependencies enabled.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="fsharp_library-generate_documentation_file"></a>generate_documentation_file |  Whether or not to generate a documentation file.   | Boolean | optional |  `True`  |
| <a id="fsharp_library-internals_visible_to"></a>internals_visible_to |  Other libraries that can see the assembly's internal symbols. Using this rather than the InternalsVisibleTo assembly attribute will improve build caching.   | List of strings | optional |  `[]`  |
| <a id="fsharp_library-keyfile"></a>keyfile |  The key file used to sign the assembly with a strong name.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="fsharp_library-langversion"></a>langversion |  The version string for the language.   | String | optional |  `""`  |
| <a id="fsharp_library-nowarn"></a>nowarn |  List of warnings that should be ignored   | List of strings | optional |  `[]`  |
| <a id="fsharp_library-project_sdk"></a>project_sdk |  The project SDK that is being targeted. See https://learn.microsoft.com/en-us/dotnet/core/project-sdk/overview   | String | optional |  `"default"`  |
| <a id="fsharp_library-target_frameworks"></a>target_frameworks |  A list of target framework monikers to buildSee https://docs.microsoft.com/en-us/dotnet/standard/frameworks   | List of strings | required |  |
| <a id="fsharp_library-treat_warnings_as_errors"></a>treat_warnings_as_errors |  Treat all compiler warnings as errors. Note that this attribute can not be used in conjunction with warnings_as_errors.   | Boolean | optional |  `False`  |
| <a id="fsharp_library-warning_level"></a>warning_level |  The warning level that should be used by the compiler.   | Integer | optional |  `3`  |
| <a id="fsharp_library-warnings_as_errors"></a>warnings_as_errors |  List of compiler warning codes that should be considered as errors. Note that this attribute can not be used in conjunction with treat_warning_as_errors.   | List of strings | optional |  `[]`  |
| <a id="fsharp_library-warnings_not_as_errors"></a>warnings_not_as_errors |  List of compiler warning codes that should not be considered as errors. Note that this attribute can only be used in conjunction with treat_warning_as_errors.   | List of strings | optional |  `[]`  |


