<!-- Generated with Stardoc: http://skydoc.bazel.build -->

Rule for compiling C# binaries.

<a id="csharp_binary"></a>

## csharp_binary

<pre>
csharp_binary(<a href="#csharp_binary-name">name</a>, <a href="#csharp_binary-deps">deps</a>, <a href="#csharp_binary-srcs">srcs</a>, <a href="#csharp_binary-data">data</a>, <a href="#csharp_binary-resources">resources</a>, <a href="#csharp_binary-out">out</a>, <a href="#csharp_binary-additionalfiles">additionalfiles</a>, <a href="#csharp_binary-allow_unsafe_blocks">allow_unsafe_blocks</a>,
              <a href="#csharp_binary-analyzer_configs">analyzer_configs</a>, <a href="#csharp_binary-appsetting_files">appsetting_files</a>, <a href="#csharp_binary-compile_data">compile_data</a>, <a href="#csharp_binary-compiler_options">compiler_options</a>, <a href="#csharp_binary-defines">defines</a>,
              <a href="#csharp_binary-generate_documentation_file">generate_documentation_file</a>, <a href="#csharp_binary-include_host_model_dll">include_host_model_dll</a>, <a href="#csharp_binary-internals_visible_to">internals_visible_to</a>, <a href="#csharp_binary-keyfile">keyfile</a>,
              <a href="#csharp_binary-langversion">langversion</a>, <a href="#csharp_binary-nowarn">nowarn</a>, <a href="#csharp_binary-nullable">nullable</a>, <a href="#csharp_binary-project_sdk">project_sdk</a>, <a href="#csharp_binary-roll_forward_behavior">roll_forward_behavior</a>, <a href="#csharp_binary-run_analyzers">run_analyzers</a>,
              <a href="#csharp_binary-target_frameworks">target_frameworks</a>, <a href="#csharp_binary-treat_warnings_as_errors">treat_warnings_as_errors</a>, <a href="#csharp_binary-warning_level">warning_level</a>, <a href="#csharp_binary-warnings_as_errors">warnings_as_errors</a>,
              <a href="#csharp_binary-warnings_not_as_errors">warnings_not_as_errors</a>, <a href="#csharp_binary-winexe">winexe</a>)
</pre>

Compile a C# exe

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="csharp_binary-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="csharp_binary-deps"></a>deps |  Other libraries, binaries, or imported DLLs   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="csharp_binary-srcs"></a>srcs |  The source files used in the compilation.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="csharp_binary-data"></a>data |  Runtime files. It is recommended to use the @rules_dotnet//tools/runfiles library to read the runtime files.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="csharp_binary-resources"></a>resources |  A list of files to embed in the DLL as resources.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="csharp_binary-out"></a>out |  File name, without extension, of the built assembly.   | String | optional |  `""`  |
| <a id="csharp_binary-additionalfiles"></a>additionalfiles |  Extra files to configure analyzers.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="csharp_binary-allow_unsafe_blocks"></a>allow_unsafe_blocks |  Allow compiling unsafe code. It true, /unsafe is passed to the compiler.   | Boolean | optional |  `False`  |
| <a id="csharp_binary-analyzer_configs"></a>analyzer_configs |  A list of analyzer configuration files. See: https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/configuration-files   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="csharp_binary-appsetting_files"></a>appsetting_files |  A list of appsettings files to include in the output directory.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="csharp_binary-compile_data"></a>compile_data |  Additional compile time files.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="csharp_binary-compiler_options"></a>compiler_options |  Additional options to pass to the compiler. This attribute should only be used if the compiler flag has not already been exposed as an attribute.   | List of strings | optional |  `[]`  |
| <a id="csharp_binary-defines"></a>defines |  A list of preprocessor directive symbols to define.   | List of strings | optional |  `[]`  |
| <a id="csharp_binary-generate_documentation_file"></a>generate_documentation_file |  Whether or not to generate a documentation file.   | Boolean | optional |  `True`  |
| <a id="csharp_binary-include_host_model_dll"></a>include_host_model_dll |  Whether to include Microsoft.NET.HostModel from the toolchain. This is only required to build tha apphost shimmer.   | Boolean | optional |  `False`  |
| <a id="csharp_binary-internals_visible_to"></a>internals_visible_to |  Other libraries that can see the assembly's internal symbols. Using this rather than the InternalsVisibleTo assembly attribute will improve build caching.   | List of strings | optional |  `[]`  |
| <a id="csharp_binary-keyfile"></a>keyfile |  The key file used to sign the assembly with a strong name.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="csharp_binary-langversion"></a>langversion |  The version string for the language.   | String | optional |  `""`  |
| <a id="csharp_binary-nowarn"></a>nowarn |  List of warnings that should be ignored   | List of strings | optional |  `["CS1701", "CS1702"]`  |
| <a id="csharp_binary-nullable"></a>nullable |  Enable nullable context, or nullable warnings.   | String | optional |  `"disable"`  |
| <a id="csharp_binary-project_sdk"></a>project_sdk |  The project SDK that is being targeted. See https://learn.microsoft.com/en-us/dotnet/core/project-sdk/overview   | String | optional |  `"default"`  |
| <a id="csharp_binary-roll_forward_behavior"></a>roll_forward_behavior |  The roll forward behavior that should be used: https://learn.microsoft.com/en-us/dotnet/core/versions/selection#control-roll-forward-behavior   | String | optional |  `"Major"`  |
| <a id="csharp_binary-run_analyzers"></a>run_analyzers |  Controls whether analyzers run at build time.   | Boolean | optional |  `True`  |
| <a id="csharp_binary-target_frameworks"></a>target_frameworks |  A list of target framework monikers to buildSee https://docs.microsoft.com/en-us/dotnet/standard/frameworks   | List of strings | required |  |
| <a id="csharp_binary-treat_warnings_as_errors"></a>treat_warnings_as_errors |  Treat all compiler warnings as errors. Note that this attribute can not be used in conjunction with warnings_as_errors.   | Boolean | optional |  `False`  |
| <a id="csharp_binary-warning_level"></a>warning_level |  The warning level that should be used by the compiler.   | Integer | optional |  `3`  |
| <a id="csharp_binary-warnings_as_errors"></a>warnings_as_errors |  List of compiler warning codes that should be considered as errors. Note that this attribute can not be used in conjunction with treat_warning_as_errors.   | List of strings | optional |  `[]`  |
| <a id="csharp_binary-warnings_not_as_errors"></a>warnings_not_as_errors |  List of compiler warning codes that should not be considered as errors. Note that this attribute can only be used in conjunction with treat_warning_as_errors.   | List of strings | optional |  `[]`  |
| <a id="csharp_binary-winexe"></a>winexe |  If true, output a winexe-style executable, otherwiseoutput a console-style executable.   | Boolean | optional |  `False`  |


