<!-- Generated with Stardoc: http://skydoc.bazel.build -->

Public API surface is re-exported here.

Users should not load files under "/dotnet"

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


<a id="csharp_library"></a>

## csharp_library

<pre>
csharp_library(<a href="#csharp_library-name">name</a>, <a href="#csharp_library-deps">deps</a>, <a href="#csharp_library-srcs">srcs</a>, <a href="#csharp_library-data">data</a>, <a href="#csharp_library-resources">resources</a>, <a href="#csharp_library-out">out</a>, <a href="#csharp_library-additionalfiles">additionalfiles</a>, <a href="#csharp_library-allow_unsafe_blocks">allow_unsafe_blocks</a>,
               <a href="#csharp_library-analyzer_configs">analyzer_configs</a>, <a href="#csharp_library-compile_data">compile_data</a>, <a href="#csharp_library-compiler_options">compiler_options</a>, <a href="#csharp_library-defines">defines</a>, <a href="#csharp_library-exports">exports</a>,
               <a href="#csharp_library-generate_documentation_file">generate_documentation_file</a>, <a href="#csharp_library-internals_visible_to">internals_visible_to</a>, <a href="#csharp_library-is_analyzer">is_analyzer</a>,
               <a href="#csharp_library-is_language_specific_analyzer">is_language_specific_analyzer</a>, <a href="#csharp_library-keyfile">keyfile</a>, <a href="#csharp_library-langversion">langversion</a>, <a href="#csharp_library-nowarn">nowarn</a>, <a href="#csharp_library-nullable">nullable</a>, <a href="#csharp_library-project_sdk">project_sdk</a>,
               <a href="#csharp_library-run_analyzers">run_analyzers</a>, <a href="#csharp_library-target_frameworks">target_frameworks</a>, <a href="#csharp_library-treat_warnings_as_errors">treat_warnings_as_errors</a>, <a href="#csharp_library-warning_level">warning_level</a>,
               <a href="#csharp_library-warnings_as_errors">warnings_as_errors</a>, <a href="#csharp_library-warnings_not_as_errors">warnings_not_as_errors</a>)
</pre>

Compile a C# DLL

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="csharp_library-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="csharp_library-deps"></a>deps |  Other libraries, binaries, or imported DLLs   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="csharp_library-srcs"></a>srcs |  The source files used in the compilation.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="csharp_library-data"></a>data |  Runtime files. It is recommended to use the @rules_dotnet//tools/runfiles library to read the runtime files.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="csharp_library-resources"></a>resources |  A list of files to embed in the DLL as resources.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="csharp_library-out"></a>out |  File name, without extension, of the built assembly.   | String | optional |  `""`  |
| <a id="csharp_library-additionalfiles"></a>additionalfiles |  Extra files to configure analyzers.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="csharp_library-allow_unsafe_blocks"></a>allow_unsafe_blocks |  Allow compiling unsafe code. It true, /unsafe is passed to the compiler.   | Boolean | optional |  `False`  |
| <a id="csharp_library-analyzer_configs"></a>analyzer_configs |  A list of analyzer configuration files. See: https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/configuration-files   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="csharp_library-compile_data"></a>compile_data |  Additional compile time files.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="csharp_library-compiler_options"></a>compiler_options |  Additional options to pass to the compiler. This attribute should only be used if the compiler flag has not already been exposed as an attribute.   | List of strings | optional |  `[]`  |
| <a id="csharp_library-defines"></a>defines |  A list of preprocessor directive symbols to define.   | List of strings | optional |  `[]`  |
| <a id="csharp_library-exports"></a>exports |  List of targets to add to the dependencies of those that depend on this target. Use this sparingly as it weakens the precision of the build graph.<br><br>This attribute does nothing if you don't have strict dependencies enabled.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="csharp_library-generate_documentation_file"></a>generate_documentation_file |  Whether or not to generate a documentation file.   | Boolean | optional |  `True`  |
| <a id="csharp_library-internals_visible_to"></a>internals_visible_to |  Other libraries that can see the assembly's internal symbols. Using this rather than the InternalsVisibleTo assembly attribute will improve build caching.   | List of strings | optional |  `[]`  |
| <a id="csharp_library-is_analyzer"></a>is_analyzer |  Whether this library is an analyzer or not. This flag is needs to be set to true if the library is an analyzer or a source generator.   | Boolean | optional |  `False`  |
| <a id="csharp_library-is_language_specific_analyzer"></a>is_language_specific_analyzer |  Whether this library is a language specific analyzer/source generator or not. This flag is needs to be set to true if the library is a analyzer that is specific to a language or if the library is a source generator.   | Boolean | optional |  `False`  |
| <a id="csharp_library-keyfile"></a>keyfile |  The key file used to sign the assembly with a strong name.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="csharp_library-langversion"></a>langversion |  The version string for the language.   | String | optional |  `""`  |
| <a id="csharp_library-nowarn"></a>nowarn |  List of warnings that should be ignored   | List of strings | optional |  `["CS1701", "CS1702"]`  |
| <a id="csharp_library-nullable"></a>nullable |  Enable nullable context, or nullable warnings.   | String | optional |  `"disable"`  |
| <a id="csharp_library-project_sdk"></a>project_sdk |  The project SDK that is being targeted. See https://learn.microsoft.com/en-us/dotnet/core/project-sdk/overview   | String | optional |  `"default"`  |
| <a id="csharp_library-run_analyzers"></a>run_analyzers |  Controls whether analyzers run at build time.   | Boolean | optional |  `True`  |
| <a id="csharp_library-target_frameworks"></a>target_frameworks |  A list of target framework monikers to buildSee https://docs.microsoft.com/en-us/dotnet/standard/frameworks   | List of strings | required |  |
| <a id="csharp_library-treat_warnings_as_errors"></a>treat_warnings_as_errors |  Treat all compiler warnings as errors. Note that this attribute can not be used in conjunction with warnings_as_errors.   | Boolean | optional |  `False`  |
| <a id="csharp_library-warning_level"></a>warning_level |  The warning level that should be used by the compiler.   | Integer | optional |  `3`  |
| <a id="csharp_library-warnings_as_errors"></a>warnings_as_errors |  List of compiler warning codes that should be considered as errors. Note that this attribute can not be used in conjunction with treat_warning_as_errors.   | List of strings | optional |  `[]`  |
| <a id="csharp_library-warnings_not_as_errors"></a>warnings_not_as_errors |  List of compiler warning codes that should not be considered as errors. Note that this attribute can only be used in conjunction with treat_warning_as_errors.   | List of strings | optional |  `[]`  |


<a id="csharp_test"></a>

## csharp_test

<pre>
csharp_test(<a href="#csharp_test-name">name</a>, <a href="#csharp_test-deps">deps</a>, <a href="#csharp_test-srcs">srcs</a>, <a href="#csharp_test-data">data</a>, <a href="#csharp_test-resources">resources</a>, <a href="#csharp_test-out">out</a>, <a href="#csharp_test-additionalfiles">additionalfiles</a>, <a href="#csharp_test-allow_unsafe_blocks">allow_unsafe_blocks</a>,
            <a href="#csharp_test-analyzer_configs">analyzer_configs</a>, <a href="#csharp_test-appsetting_files">appsetting_files</a>, <a href="#csharp_test-compile_data">compile_data</a>, <a href="#csharp_test-compiler_options">compiler_options</a>, <a href="#csharp_test-defines">defines</a>,
            <a href="#csharp_test-generate_documentation_file">generate_documentation_file</a>, <a href="#csharp_test-internals_visible_to">internals_visible_to</a>, <a href="#csharp_test-keyfile">keyfile</a>, <a href="#csharp_test-langversion">langversion</a>, <a href="#csharp_test-nowarn">nowarn</a>, <a href="#csharp_test-nullable">nullable</a>,
            <a href="#csharp_test-project_sdk">project_sdk</a>, <a href="#csharp_test-roll_forward_behavior">roll_forward_behavior</a>, <a href="#csharp_test-run_analyzers">run_analyzers</a>, <a href="#csharp_test-target_frameworks">target_frameworks</a>,
            <a href="#csharp_test-treat_warnings_as_errors">treat_warnings_as_errors</a>, <a href="#csharp_test-warning_level">warning_level</a>, <a href="#csharp_test-warnings_as_errors">warnings_as_errors</a>, <a href="#csharp_test-warnings_not_as_errors">warnings_not_as_errors</a>,
            <a href="#csharp_test-winexe">winexe</a>)
</pre>

Compiles a C# executable and runs it as a test

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="csharp_test-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="csharp_test-deps"></a>deps |  Other libraries, binaries, or imported DLLs   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="csharp_test-srcs"></a>srcs |  The source files used in the compilation.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="csharp_test-data"></a>data |  Runtime files. It is recommended to use the @rules_dotnet//tools/runfiles library to read the runtime files.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="csharp_test-resources"></a>resources |  A list of files to embed in the DLL as resources.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="csharp_test-out"></a>out |  File name, without extension, of the built assembly.   | String | optional |  `""`  |
| <a id="csharp_test-additionalfiles"></a>additionalfiles |  Extra files to configure analyzers.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="csharp_test-allow_unsafe_blocks"></a>allow_unsafe_blocks |  Allow compiling unsafe code. It true, /unsafe is passed to the compiler.   | Boolean | optional |  `False`  |
| <a id="csharp_test-analyzer_configs"></a>analyzer_configs |  A list of analyzer configuration files. See: https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/configuration-files   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="csharp_test-appsetting_files"></a>appsetting_files |  A list of appsettings files to include in the output directory.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="csharp_test-compile_data"></a>compile_data |  Additional compile time files.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="csharp_test-compiler_options"></a>compiler_options |  Additional options to pass to the compiler. This attribute should only be used if the compiler flag has not already been exposed as an attribute.   | List of strings | optional |  `[]`  |
| <a id="csharp_test-defines"></a>defines |  A list of preprocessor directive symbols to define.   | List of strings | optional |  `[]`  |
| <a id="csharp_test-generate_documentation_file"></a>generate_documentation_file |  Whether or not to generate a documentation file.   | Boolean | optional |  `True`  |
| <a id="csharp_test-internals_visible_to"></a>internals_visible_to |  Other libraries that can see the assembly's internal symbols. Using this rather than the InternalsVisibleTo assembly attribute will improve build caching.   | List of strings | optional |  `[]`  |
| <a id="csharp_test-keyfile"></a>keyfile |  The key file used to sign the assembly with a strong name.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="csharp_test-langversion"></a>langversion |  The version string for the language.   | String | optional |  `""`  |
| <a id="csharp_test-nowarn"></a>nowarn |  List of warnings that should be ignored   | List of strings | optional |  `["CS1701", "CS1702"]`  |
| <a id="csharp_test-nullable"></a>nullable |  Enable nullable context, or nullable warnings.   | String | optional |  `"disable"`  |
| <a id="csharp_test-project_sdk"></a>project_sdk |  The project SDK that is being targeted. See https://learn.microsoft.com/en-us/dotnet/core/project-sdk/overview   | String | optional |  `"default"`  |
| <a id="csharp_test-roll_forward_behavior"></a>roll_forward_behavior |  The roll forward behavior that should be used: https://learn.microsoft.com/en-us/dotnet/core/versions/selection#control-roll-forward-behavior   | String | optional |  `"Major"`  |
| <a id="csharp_test-run_analyzers"></a>run_analyzers |  Controls whether analyzers run at build time.   | Boolean | optional |  `True`  |
| <a id="csharp_test-target_frameworks"></a>target_frameworks |  A list of target framework monikers to buildSee https://docs.microsoft.com/en-us/dotnet/standard/frameworks   | List of strings | required |  |
| <a id="csharp_test-treat_warnings_as_errors"></a>treat_warnings_as_errors |  Treat all compiler warnings as errors. Note that this attribute can not be used in conjunction with warnings_as_errors.   | Boolean | optional |  `False`  |
| <a id="csharp_test-warning_level"></a>warning_level |  The warning level that should be used by the compiler.   | Integer | optional |  `3`  |
| <a id="csharp_test-warnings_as_errors"></a>warnings_as_errors |  List of compiler warning codes that should be considered as errors. Note that this attribute can not be used in conjunction with treat_warning_as_errors.   | List of strings | optional |  `[]`  |
| <a id="csharp_test-warnings_not_as_errors"></a>warnings_not_as_errors |  List of compiler warning codes that should not be considered as errors. Note that this attribute can only be used in conjunction with treat_warning_as_errors.   | List of strings | optional |  `[]`  |
| <a id="csharp_test-winexe"></a>winexe |  If true, output a winexe-style executable, otherwiseoutput a console-style executable.   | Boolean | optional |  `False`  |


<a id="fsharp_binary"></a>

## fsharp_binary

<pre>
fsharp_binary(<a href="#fsharp_binary-name">name</a>, <a href="#fsharp_binary-deps">deps</a>, <a href="#fsharp_binary-srcs">srcs</a>, <a href="#fsharp_binary-data">data</a>, <a href="#fsharp_binary-resources">resources</a>, <a href="#fsharp_binary-out">out</a>, <a href="#fsharp_binary-appsetting_files">appsetting_files</a>, <a href="#fsharp_binary-compile_data">compile_data</a>,
              <a href="#fsharp_binary-compiler_options">compiler_options</a>, <a href="#fsharp_binary-defines">defines</a>, <a href="#fsharp_binary-generate_documentation_file">generate_documentation_file</a>, <a href="#fsharp_binary-internals_visible_to">internals_visible_to</a>, <a href="#fsharp_binary-keyfile">keyfile</a>,
              <a href="#fsharp_binary-langversion">langversion</a>, <a href="#fsharp_binary-nowarn">nowarn</a>, <a href="#fsharp_binary-project_sdk">project_sdk</a>, <a href="#fsharp_binary-roll_forward_behavior">roll_forward_behavior</a>, <a href="#fsharp_binary-target_frameworks">target_frameworks</a>,
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


<a id="fsharp_library"></a>

## fsharp_library

<pre>
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


<a id="fsharp_test"></a>

## fsharp_test

<pre>
fsharp_test(<a href="#fsharp_test-name">name</a>, <a href="#fsharp_test-deps">deps</a>, <a href="#fsharp_test-srcs">srcs</a>, <a href="#fsharp_test-data">data</a>, <a href="#fsharp_test-resources">resources</a>, <a href="#fsharp_test-out">out</a>, <a href="#fsharp_test-appsetting_files">appsetting_files</a>, <a href="#fsharp_test-compile_data">compile_data</a>,
            <a href="#fsharp_test-compiler_options">compiler_options</a>, <a href="#fsharp_test-defines">defines</a>, <a href="#fsharp_test-generate_documentation_file">generate_documentation_file</a>, <a href="#fsharp_test-internals_visible_to">internals_visible_to</a>, <a href="#fsharp_test-keyfile">keyfile</a>,
            <a href="#fsharp_test-langversion">langversion</a>, <a href="#fsharp_test-nowarn">nowarn</a>, <a href="#fsharp_test-project_sdk">project_sdk</a>, <a href="#fsharp_test-roll_forward_behavior">roll_forward_behavior</a>, <a href="#fsharp_test-target_frameworks">target_frameworks</a>,
            <a href="#fsharp_test-treat_warnings_as_errors">treat_warnings_as_errors</a>, <a href="#fsharp_test-warning_level">warning_level</a>, <a href="#fsharp_test-warnings_as_errors">warnings_as_errors</a>, <a href="#fsharp_test-warnings_not_as_errors">warnings_not_as_errors</a>,
            <a href="#fsharp_test-winexe">winexe</a>)
</pre>

Compile a F# executable and runs it as a test

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="fsharp_test-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="fsharp_test-deps"></a>deps |  Other libraries, binaries, or imported DLLs   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="fsharp_test-srcs"></a>srcs |  The source files used in the compilation.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="fsharp_test-data"></a>data |  Runtime files. It is recommended to use the @rules_dotnet//tools/runfiles library to read the runtime files.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="fsharp_test-resources"></a>resources |  A list of files to embed in the DLL as resources.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="fsharp_test-out"></a>out |  File name, without extension, of the built assembly.   | String | optional |  `""`  |
| <a id="fsharp_test-appsetting_files"></a>appsetting_files |  A list of appsettings files to include in the output directory.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="fsharp_test-compile_data"></a>compile_data |  Additional compile time files.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="fsharp_test-compiler_options"></a>compiler_options |  Additional options to pass to the compiler. This attribute should only be used if the compiler flag has not already been exposed as an attribute.   | List of strings | optional |  `[]`  |
| <a id="fsharp_test-defines"></a>defines |  A list of preprocessor directive symbols to define.   | List of strings | optional |  `[]`  |
| <a id="fsharp_test-generate_documentation_file"></a>generate_documentation_file |  Whether or not to generate a documentation file.   | Boolean | optional |  `True`  |
| <a id="fsharp_test-internals_visible_to"></a>internals_visible_to |  Other libraries that can see the assembly's internal symbols. Using this rather than the InternalsVisibleTo assembly attribute will improve build caching.   | List of strings | optional |  `[]`  |
| <a id="fsharp_test-keyfile"></a>keyfile |  The key file used to sign the assembly with a strong name.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="fsharp_test-langversion"></a>langversion |  The version string for the language.   | String | optional |  `""`  |
| <a id="fsharp_test-nowarn"></a>nowarn |  List of warnings that should be ignored   | List of strings | optional |  `[]`  |
| <a id="fsharp_test-project_sdk"></a>project_sdk |  The project SDK that is being targeted. See https://learn.microsoft.com/en-us/dotnet/core/project-sdk/overview   | String | optional |  `"default"`  |
| <a id="fsharp_test-roll_forward_behavior"></a>roll_forward_behavior |  The roll forward behavior that should be used: https://learn.microsoft.com/en-us/dotnet/core/versions/selection#control-roll-forward-behavior   | String | optional |  `"Major"`  |
| <a id="fsharp_test-target_frameworks"></a>target_frameworks |  A list of target framework monikers to buildSee https://docs.microsoft.com/en-us/dotnet/standard/frameworks   | List of strings | required |  |
| <a id="fsharp_test-treat_warnings_as_errors"></a>treat_warnings_as_errors |  Treat all compiler warnings as errors. Note that this attribute can not be used in conjunction with warnings_as_errors.   | Boolean | optional |  `False`  |
| <a id="fsharp_test-warning_level"></a>warning_level |  The warning level that should be used by the compiler.   | Integer | optional |  `3`  |
| <a id="fsharp_test-warnings_as_errors"></a>warnings_as_errors |  List of compiler warning codes that should be considered as errors. Note that this attribute can not be used in conjunction with treat_warning_as_errors.   | List of strings | optional |  `[]`  |
| <a id="fsharp_test-warnings_not_as_errors"></a>warnings_not_as_errors |  List of compiler warning codes that should not be considered as errors. Note that this attribute can only be used in conjunction with treat_warning_as_errors.   | List of strings | optional |  `[]`  |
| <a id="fsharp_test-winexe"></a>winexe |  If true, output a winexe-style executable, otherwiseoutput a console-style executable.   | Boolean | optional |  `False`  |


<a id="import_dll"></a>

## import_dll

<pre>
import_dll(<a href="#import_dll-name">name</a>, <a href="#import_dll-data">data</a>, <a href="#import_dll-dll">dll</a>, <a href="#import_dll-version">version</a>)
</pre>

Imports a DLL

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="import_dll-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="import_dll-data"></a>data |  Other files that this DLL depends on at runtime   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="import_dll-dll"></a>dll |  The name of the library   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |
| <a id="import_dll-version"></a>version |  The version of the library   | String | optional |  `""`  |


<a id="import_library"></a>

## import_library

<pre>
import_library(<a href="#import_library-name">name</a>, <a href="#import_library-deps">deps</a>, <a href="#import_library-data">data</a>, <a href="#import_library-analyzers">analyzers</a>, <a href="#import_library-analyzers_csharp">analyzers_csharp</a>, <a href="#import_library-analyzers_fsharp">analyzers_fsharp</a>, <a href="#import_library-analyzers_vb">analyzers_vb</a>,
               <a href="#import_library-framework_list">framework_list</a>, <a href="#import_library-library_name">library_name</a>, <a href="#import_library-libs">libs</a>, <a href="#import_library-native">native</a>, <a href="#import_library-nupkg">nupkg</a>, <a href="#import_library-refs">refs</a>, <a href="#import_library-sha512">sha512</a>,
               <a href="#import_library-targeting_pack_overrides">targeting_pack_overrides</a>, <a href="#import_library-version">version</a>)
</pre>

Creates a target for a static DLL for a specific target framework

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="import_library-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="import_library-deps"></a>deps |  Other DLLs that this DLL depends on.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="import_library-data"></a>data |  Other files that this DLL depends on at runtime   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="import_library-analyzers"></a>analyzers |  Static analyzer DLLs   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="import_library-analyzers_csharp"></a>analyzers_csharp |  Static C# analyzer DLLs   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="import_library-analyzers_fsharp"></a>analyzers_fsharp |  Static F# analyzer DLLs   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="import_library-analyzers_vb"></a>analyzers_vb |  Static VB analyzer DLLs   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="import_library-framework_list"></a>framework_list |  Targeting packs like e.g. Microsoft.NETCore.App.Ref have a PlatformManifest.txt that includes all the DLLs that are included in the targeting pack. This is used to determine which version of a DLL should be used during compilation or runtime.   | <a href="https://bazel.build/rules/lib/dict">Dictionary: String -> String</a> | optional |  `{}`  |
| <a id="import_library-library_name"></a>library_name |  The name of the library   | String | required |  |
| <a id="import_library-libs"></a>libs |  Static runtime DLLs   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="import_library-native"></a>native |  Native runtime DLLs   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="import_library-nupkg"></a>nupkg |  The `.nupkg` file providing this import   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="import_library-refs"></a>refs |  Compile time DLLs   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="import_library-sha512"></a>sha512 |  The SHA512 sum of the NuGet package   | String | optional |  `""`  |
| <a id="import_library-targeting_pack_overrides"></a>targeting_pack_overrides |  Targeting packs like e.g. Microsoft.NETCore.App.Ref have a PackageOverride.txt that includes a list of NuGet packages that should be omitted in a compiliation because they are included in the targeting pack   | <a href="https://bazel.build/rules/lib/dict">Dictionary: String -> String</a> | optional |  `{}`  |
| <a id="import_library-version"></a>version |  The version of the library   | String | optional |  `""`  |


<a id="publish_binary"></a>

## publish_binary

<pre>
publish_binary(<a href="#publish_binary-name">name</a>, <a href="#publish_binary-binary">binary</a>, <a href="#publish_binary-roll_forward_behavior">roll_forward_behavior</a>, <a href="#publish_binary-runtime_identifier">runtime_identifier</a>, <a href="#publish_binary-self_contained">self_contained</a>,
               <a href="#publish_binary-target_framework">target_framework</a>)
</pre>

Publish a .Net binary

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="publish_binary-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="publish_binary-binary"></a>binary |  The .Net binary that is being published   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |
| <a id="publish_binary-roll_forward_behavior"></a>roll_forward_behavior |  The roll forward behavior that should be used: https://learn.microsoft.com/en-us/dotnet/core/versions/selection#control-roll-forward-behavior   | String | optional |  `"Minor"`  |
| <a id="publish_binary-runtime_identifier"></a>runtime_identifier |  The runtime identifier that is being targeted. See https://docs.microsoft.com/en-us/dotnet/core/rid-catalog   | String | optional |  `""`  |
| <a id="publish_binary-self_contained"></a>self_contained |  Whether the binary should be self-contained.<br><br>If true, the binary will be published as a self-contained but you need to provide a runtime pack in the `runtime_packs` attribute. At some point the rules might resolve the runtime pack automatically.<br><br>If false, the binary will be published as a non-self-contained. That means that to be able to run the binary you need to have a .Net runtime installed on the host system.   | Boolean | optional |  `False`  |
| <a id="publish_binary-target_framework"></a>target_framework |  The target framework that should be published   | String | required |  |


<a id="csharp_nunit_test"></a>

## csharp_nunit_test

<pre>
csharp_nunit_test(<a href="#csharp_nunit_test-kwargs">kwargs</a>)
</pre>



**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="csharp_nunit_test-kwargs"></a>kwargs |  <p align="center"> - </p>   |  none |


<a id="fsharp_nunit_test"></a>

## fsharp_nunit_test

<pre>
fsharp_nunit_test(<a href="#fsharp_nunit_test-kwargs">kwargs</a>)
</pre>



**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="fsharp_nunit_test-kwargs"></a>kwargs |  <p align="center"> - </p>   |  none |


<a id="nuget_repo"></a>

## nuget_repo

<pre>
nuget_repo(<a href="#nuget_repo-name">name</a>, <a href="#nuget_repo-packages">packages</a>)
</pre>



**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="nuget_repo-name"></a>name |  <p align="center"> - </p>   |  none |
| <a id="nuget_repo-packages"></a>packages |  <p align="center"> - </p>   |  none |


<a id="nuget_archive"></a>

## nuget_archive

<pre>
nuget_archive(<a href="#nuget_archive-name">name</a>, <a href="#nuget_archive-id">id</a>, <a href="#nuget_archive-netrc">netrc</a>, <a href="#nuget_archive-repo_mapping">repo_mapping</a>, <a href="#nuget_archive-sha512">sha512</a>, <a href="#nuget_archive-sources">sources</a>, <a href="#nuget_archive-version">version</a>)
</pre>

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="nuget_archive-name"></a>name |  A unique name for this repository.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="nuget_archive-id"></a>id |  -   | String | optional |  `""`  |
| <a id="nuget_archive-netrc"></a>netrc |  -   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="nuget_archive-repo_mapping"></a>repo_mapping |  In `WORKSPACE` context only: a dictionary from local repository name to global repository name. This allows controls over workspace dependency resolution for dependencies of this repository.<br><br>For example, an entry `"@foo": "@bar"` declares that, for any time this repository depends on `@foo` (such as a dependency on `@foo//some:target`, it should actually resolve that dependency within globally-declared `@bar` (`@bar//some:target`).<br><br>This attribute is _not_ supported in `MODULE.bazel` context (when invoking a repository rule inside a module extension's implementation function).   | <a href="https://bazel.build/rules/lib/dict">Dictionary: String -> String</a> | optional |  |
| <a id="nuget_archive-sha512"></a>sha512 |  -   | String | optional |  `""`  |
| <a id="nuget_archive-sources"></a>sources |  -   | List of strings | optional |  `[]`  |
| <a id="nuget_archive-version"></a>version |  -   | String | optional |  `""`  |


