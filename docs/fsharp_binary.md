<!-- Generated with Stardoc: http://skydoc.bazel.build -->

Rule for compiling F# binaries.

<a id="fsharp_binary"></a>

## fsharp_binary

<pre>
load("@rules_dotnet//dotnet/private/rules/fsharp:binary.bzl", "fsharp_binary")

fsharp_binary(<a href="#fsharp_binary-name">name</a>, <a href="#fsharp_binary-deps">deps</a>, <a href="#fsharp_binary-srcs">srcs</a>, <a href="#fsharp_binary-data">data</a>, <a href="#fsharp_binary-resources">resources</a>, <a href="#fsharp_binary-out">out</a>, <a href="#fsharp_binary-appsetting_files">appsetting_files</a>, <a href="#fsharp_binary-compile_data">compile_data</a>,
              <a href="#fsharp_binary-compiler_options">compiler_options</a>, <a href="#fsharp_binary-defines">defines</a>, <a href="#fsharp_binary-envs">envs</a>, <a href="#fsharp_binary-generate_documentation_file">generate_documentation_file</a>, <a href="#fsharp_binary-internals_visible_to">internals_visible_to</a>,
              <a href="#fsharp_binary-keyfile">keyfile</a>, <a href="#fsharp_binary-langversion">langversion</a>, <a href="#fsharp_binary-nowarn">nowarn</a>, <a href="#fsharp_binary-project_sdk">project_sdk</a>, <a href="#fsharp_binary-roll_forward_behavior">roll_forward_behavior</a>, <a href="#fsharp_binary-target_frameworks">target_frameworks</a>,
              <a href="#fsharp_binary-treat_warnings_as_errors">treat_warnings_as_errors</a>, <a href="#fsharp_binary-warning_level">warning_level</a>, <a href="#fsharp_binary-warnings_as_errors">warnings_as_errors</a>, <a href="#fsharp_binary-warnings_not_as_errors">warnings_not_as_errors</a>,
              <a href="#fsharp_binary-winexe">winexe</a>)
</pre>

Compile a F# exe

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="fsharp_binary-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="fsharp_binary-deps"></a>deps |  Other libraries, binaries, or imported DLLs   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="fsharp_binary-srcs"></a>srcs |  The source files used in the compilation.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="fsharp_binary-data"></a>data |  Runtime files. It is recommended to use the @rules_dotnet//tools/runfiles library to read the runtime files.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="fsharp_binary-resources"></a>resources |  A list of files to embed in the DLL as resources.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="fsharp_binary-out"></a>out |  File name, without extension, of the built assembly.   | String | optional |  `""`  |
| <a id="fsharp_binary-appsetting_files"></a>appsetting_files |  A list of appsettings files to include in the output directory.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="fsharp_binary-compile_data"></a>compile_data |  Additional compile time files.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="fsharp_binary-compiler_options"></a>compiler_options |  Additional options to pass to the compiler. This attribute should only be used if the compiler flag has not already been exposed as an attribute.   | List of strings | optional |  `[]`  |
| <a id="fsharp_binary-defines"></a>defines |  A list of preprocessor directive symbols to define.   | List of strings | optional |  `[]`  |
| <a id="fsharp_binary-envs"></a>envs |  A dictionary of environment variables to set when the binary is run. Supports make variable expansion   | <a href="https://bazel.build/rules/lib/dict">Dictionary: String -> String</a> | optional |  `{}`  |
| <a id="fsharp_binary-generate_documentation_file"></a>generate_documentation_file |  Whether or not to generate a documentation file.   | Boolean | optional |  `True`  |
| <a id="fsharp_binary-internals_visible_to"></a>internals_visible_to |  Other libraries that can see the assembly's internal symbols. Using this rather than the InternalsVisibleTo assembly attribute will improve build caching.   | List of strings | optional |  `[]`  |
| <a id="fsharp_binary-keyfile"></a>keyfile |  The key file used to sign the assembly with a strong name.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="fsharp_binary-langversion"></a>langversion |  The version string for the language.   | String | optional |  `""`  |
| <a id="fsharp_binary-nowarn"></a>nowarn |  List of warnings that should be ignored   | List of strings | optional |  `[]`  |
| <a id="fsharp_binary-project_sdk"></a>project_sdk |  The project SDK that is being targeted. See https://learn.microsoft.com/en-us/dotnet/core/project-sdk/overview   | String | optional |  `"default"`  |
| <a id="fsharp_binary-roll_forward_behavior"></a>roll_forward_behavior |  The roll forward behavior that should be used: https://learn.microsoft.com/en-us/dotnet/core/versions/selection#control-roll-forward-behavior   | String | optional |  `"Major"`  |
| <a id="fsharp_binary-target_frameworks"></a>target_frameworks |  A list of target framework monikers to buildSee https://docs.microsoft.com/en-us/dotnet/standard/frameworks   | List of strings | required |  |
| <a id="fsharp_binary-treat_warnings_as_errors"></a>treat_warnings_as_errors |  Treat all compiler warnings as errors. Note that this attribute can not be used in conjunction with warnings_as_errors.   | Boolean | optional |  `False`  |
| <a id="fsharp_binary-warning_level"></a>warning_level |  The warning level that should be used by the compiler.   | Integer | optional |  `3`  |
| <a id="fsharp_binary-warnings_as_errors"></a>warnings_as_errors |  List of compiler warning codes that should be considered as errors. Note that this attribute can not be used in conjunction with treat_warning_as_errors.   | List of strings | optional |  `[]`  |
| <a id="fsharp_binary-warnings_not_as_errors"></a>warnings_not_as_errors |  List of compiler warning codes that should not be considered as errors. Note that this attribute can only be used in conjunction with treat_warning_as_errors.   | List of strings | optional |  `[]`  |
| <a id="fsharp_binary-winexe"></a>winexe |  If true, output a winexe-style executable, otherwiseoutput a console-style executable.   | Boolean | optional |  `False`  |


