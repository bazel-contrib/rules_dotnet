"Utilities for parsing .csproj and .fsproj files using xml.bzl"

load("@xml.bzl", "xml")

def parse_project_file(content):
    """Parse a .csproj or .fsproj file and extract relevant information.

    Args:
        content: The XML content of the project file as a string.

    Returns:
        A struct containing:
            - sdk: The SDK type (e.g., "Microsoft.NET.Sdk", "Microsoft.NET.Sdk.Web")
            - target_frameworks: List of target framework monikers
            - output_type: "Exe", "Library", or "WinExe"
            - sources: List of explicit source file paths (from Compile items)
            - project_references: List of relative paths to referenced projects
            - package_references: List of structs with id and version
            - properties: Dict of other relevant properties
            - enable_default_items: Whether default items are enabled (affects source glob)
            - is_fsharp: Whether this is an F# project
            - errors: List of parsing errors
    """
    doc = xml.parse(content)

    if xml.has_errors(doc):
        return struct(
            sdk = "Microsoft.NET.Sdk",
            target_frameworks = [],
            output_type = "Library",
            sources = [],
            project_references = [],
            package_references = [],
            properties = {},
            enable_default_items = True,
            is_fsharp = False,
            errors = [e.message for e in xml.get_errors(doc)],
        )

    root = xml.get_document_element(doc)
    if root == None:
        return struct(
            sdk = "Microsoft.NET.Sdk",
            target_frameworks = [],
            output_type = "Library",
            sources = [],
            project_references = [],
            package_references = [],
            properties = {},
            enable_default_items = True,
            is_fsharp = False,
            errors = ["No root element found"],
        )

    # Extract SDK from Project element
    sdk = xml.get_attribute(root, "Sdk", "Microsoft.NET.Sdk")

    # Extract properties from PropertyGroup elements
    properties = _extract_properties(root)

    # Determine target frameworks
    target_frameworks = _extract_target_frameworks(properties)

    # Extract output type
    output_type = properties.get("OutputType", "Library")

    # Check if default items are enabled (default is true for SDK-style projects)
    enable_default_items_str = properties.get("EnableDefaultItems", "true")
    enable_default_items = enable_default_items_str.lower() == "true"

    # Extract source files from Compile items
    sources = _extract_compile_items(root)

    # Extract project references
    project_references = _extract_project_references(root)

    # Extract package references
    package_references = _extract_package_references(root)

    return struct(
        sdk = sdk,
        target_frameworks = target_frameworks,
        output_type = output_type,
        sources = sources,
        project_references = project_references,
        package_references = package_references,
        properties = properties,
        enable_default_items = enable_default_items,
        is_fsharp = False,  # Will be set by caller based on file extension
        errors = [],
    )

def _extract_properties(root):
    """Extract all properties from PropertyGroup elements.

    Args:
        root: The root Project element.

    Returns:
        Dict mapping property names to their values.
    """
    properties = {}

    for property_group in xml.find_elements_by_tag_name(root, "PropertyGroup"):
        for child in xml.get_child_elements(property_group):
            tag_name = xml.get_tag_name(child)
            text = xml.get_text(child)
            if text:
                properties[tag_name] = text.strip()

    return properties

def _extract_target_frameworks(properties):
    """Extract target frameworks from properties.

    Handles both TargetFramework (single) and TargetFrameworks (multiple).

    Args:
        properties: Dict of properties from PropertyGroup elements.

    Returns:
        List of target framework monikers.
    """

    # Check for multiple frameworks first
    if "TargetFrameworks" in properties:
        frameworks_str = properties["TargetFrameworks"]
        return [f.strip() for f in frameworks_str.split(";") if f.strip()]

    # Single framework
    if "TargetFramework" in properties:
        return [properties["TargetFramework"]]

    return []

def _extract_compile_items(root):
    """Extract source files from Compile items.

    Args:
        root: The root Project element.

    Returns:
        List of source file paths (relative to project file).
    """
    sources = []

    for item_group in xml.find_elements_by_tag_name(root, "ItemGroup"):
        for compile in xml.find_elements_by_tag_name(item_group, "Compile"):
            include = xml.get_attribute(compile, "Include")
            if include:
                # Normalize path separators
                normalized = include.replace("\\", "/")
                sources.append(normalized)

    return sources

def _extract_project_references(root):
    """Extract project references from ProjectReference items.

    Args:
        root: The root Project element.

    Returns:
        List of structs with path (relative path to referenced project).
    """
    refs = []

    for item_group in xml.find_elements_by_tag_name(root, "ItemGroup"):
        for proj_ref in xml.find_elements_by_tag_name(item_group, "ProjectReference"):
            include = xml.get_attribute(proj_ref, "Include")
            if include:
                # Normalize path separators
                normalized = include.replace("\\", "/")
                refs.append(struct(path = normalized))

    return refs

def _extract_package_references(root):
    """Extract NuGet package references from PackageReference items.

    Args:
        root: The root Project element.

    Returns:
        List of structs with id and version.
    """
    packages = []

    for item_group in xml.find_elements_by_tag_name(root, "ItemGroup"):
        for pkg_ref in xml.find_elements_by_tag_name(item_group, "PackageReference"):
            package_id = xml.get_attribute(pkg_ref, "Include")
            version = xml.get_attribute(pkg_ref, "Version")

            # Version might be in a child element instead of attribute
            if not version:
                version_elem = xml.find_element_by_tag_name(pkg_ref, "Version")
                if version_elem:
                    version = xml.get_text(version_elem)
                    if version:
                        version = version.strip()

            if package_id:
                packages.append(struct(
                    id = package_id,
                    version = version or "",
                ))

    return packages

def get_project_type(parsed_project):
    """Determine the Bazel rule type for a parsed project.

    Args:
        parsed_project: A struct returned by parse_project_file.

    Returns:
        One of: "library", "binary", "test"
    """
    output_type = parsed_project.output_type.lower() if parsed_project.output_type else "library"

    if output_type == "exe" or output_type == "winexe":
        return "binary"

    # Check if it's a test project
    is_test = parsed_project.properties.get("IsTestProject", "false").lower() == "true"
    if is_test:
        return "test"

    return "library"

def get_bazel_rule_name(parsed_project, is_fsharp):
    """Get the Bazel rule name for a parsed project.

    Args:
        parsed_project: A struct returned by parse_project_file.
        is_fsharp: Whether this is an F# project.

    Returns:
        The Bazel rule name (e.g., "csharp_library", "fsharp_binary").
    """
    project_type = get_project_type(parsed_project)
    lang_prefix = "fsharp" if is_fsharp else "csharp"

    return "{}_{}".format(lang_prefix, project_type)

def get_project_sdk_attr(parsed_project):
    """Get the project_sdk attribute value if needed.

    Args:
        parsed_project: A struct returned by parse_project_file.

    Returns:
        "web" if this is a web SDK project, None otherwise.
    """
    if "Web" in parsed_project.sdk:
        return "web"
    return None

def extract_additional_attrs(parsed_project):
    """Extract additional Bazel attributes from project properties.

    Args:
        parsed_project: A struct returned by parse_project_file.

    Returns:
        Dict of additional attributes to pass to the Bazel rule.
    """
    attrs = {}
    props = parsed_project.properties

    # Nullable
    if "Nullable" in props:
        attrs["nullable"] = props["Nullable"].lower()

    # Language version
    if "LangVersion" in props:
        attrs["langversion"] = props["LangVersion"]

    # Treat warnings as errors
    if "TreatWarningsAsErrors" in props:
        attrs["treat_warnings_as_errors"] = props["TreatWarningsAsErrors"].lower() == "true"

    # Warning level
    if "WarningLevel" in props:
        level = props["WarningLevel"]
        if level.isdigit():
            attrs["warning_level"] = int(level)

    # Allow unsafe blocks (C# only)
    if "AllowUnsafeBlocks" in props:
        attrs["allow_unsafe_blocks"] = props["AllowUnsafeBlocks"].lower() == "true"

    return attrs
