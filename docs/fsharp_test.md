<!-- Generated with Stardoc: http://skydoc.bazel.build -->

Rule for compiling and running test binaries.

This rule can be used to compile and run any F# binary and run it as
a Bazel test.

<a id="fsharp_test"></a>

## fsharp_test

<pre>
fsharp_test(<a href="#fsharp_test-name">name</a>, <a href="#fsharp_test-deps">deps</a>, <a href="#fsharp_test-srcs">srcs</a>, <a href="#fsharp_test-data">data</a>, <a href="#fsharp_test-resources">resources</a>, <a href="#fsharp_test-out">out</a>, <a href="#fsharp_test-appsetting_files">appsetting_files</a>, <a href="#fsharp_test-compile_data">compile_data</a>,
            <a href="#fsharp_test-compiler_options">compiler_options</a>, <a href="#fsharp_test-defines">defines</a>, <a href="#fsharp_test-envs">envs</a>, <a href="#fsharp_test-generate_documentation_file">generate_documentation_file</a>, <a href="#fsharp_test-internals_visible_to">internals_visible_to</a>,
            <a href="#fsharp_test-keyfile">keyfile</a>, <a href="#fsharp_test-langversion">langversion</a>, <a href="#fsharp_test-nowarn">nowarn</a>, <a href="#fsharp_test-project_sdk">project_sdk</a>, <a href="#fsharp_test-roll_forward_behavior">roll_forward_behavior</a>, <a href="#fsharp_test-target_frameworks">target_frameworks</a>,
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
| <a id="fsharp_test-envs"></a>envs |  A dictionary of environment variables to set when the binary is run. Supports make variable expansion   | <a href="https://bazel.build/rules/lib/dict">Dictionary: String -> String</a> | optional |  `{}`  |
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


