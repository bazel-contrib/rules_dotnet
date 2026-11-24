"""Reads the SDK version a `global.json` pins."""

_CODE = "code"
_STRING = "string"
_ESCAPE = "escape"
_LINE_COMMENT = "line_comment"
_BLOCK_COMMENT = "block_comment"

_WHITESPACE = " \t\r\n"

def _drop_trailing_comma(out):
    for i in range(len(out) - 1, -1, -1):
        if out[i] not in _WHITESPACE:
            if out[i] == ",":
                out.pop(i)
            return

def _to_strict_json(text):
    """Drops the comments and trailing commas the dotnet CLI accepts in global.json.

    Args:
      text: The content of a global.json.

    Returns:
      The content as strict JSON, starting at its top-level object.
    """
    out = []
    state = _CODE
    skip = False

    for i in range(len(text)):
        if skip:
            skip = False
            continue

        char = text[i]
        following = text[i + 1:i + 2]

        if state == _STRING:
            out.append(char)
            if char == "\\":
                state = _ESCAPE
            elif char == "\"":
                state = _CODE
        elif state == _ESCAPE:
            out.append(char)
            state = _STRING
        elif state == _LINE_COMMENT:
            if char == "\n":
                out.append(char)
                state = _CODE
        elif state == _BLOCK_COMMENT:
            if char == "*" and following == "/":
                skip = True
                state = _CODE
        elif char == "/" and following in ["/", "*"]:
            out.append(" ")
            skip = True
            state = _LINE_COMMENT if following == "/" else _BLOCK_COMMENT
        else:
            if char in "}]":
                _drop_trailing_comma(out)
            elif char == "\"":
                state = _STRING
            out.append(char)

    # Also skips a byte order mark.
    strict = "".join(out)
    start = strict.find("{")
    return strict[start:] if start >= 0 else strict

def global_json_sdk_version(content, name):
    """Returns the `sdk.version` of a global.json.

    Comments and trailing commas are accepted, as the dotnet CLI accepts them.

    Args:
      content: The content of the global.json.
      name: What to call the file in errors.

    Returns:
      The SDK version.
    """
    document = json.decode(_to_strict_json(content), default = None)
    if type(document) != "dict":
        fail("{} is not a JSON object".format(name))

    sdk = document.get("sdk")
    version = sdk.get("version") if type(sdk) == "dict" else None
    if type(version) != "string" or not version:
        fail("{} has no sdk.version for dotnet.toolchain to use".format(name))

    return version
