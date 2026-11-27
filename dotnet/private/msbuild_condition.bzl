"""Evaluates the MSBuild conditions the .NET SDK puts on the items rules_dotnet reads from it.

Only the subset the SDK's props use is understood:

  * string operands: `'...'`, `$(Property)`, and bare words such as `true`;
  * `==` and `!=`, compared case-insensitively as MSBuild does;
  * `and`, `or`, `!` and parentheses;
  * the `[MSBuild]::Version*` property functions.

Anything else is reported as an error rather than guessed at, so that a newer
SDK using a construct this does not know about fails loudly instead of
silently diverging from MSBuild.

Properties are looked up case-insensitively, and an undefined one is the empty
string, as in MSBuild.

Starlark has no recursion, so the expression is converted to postfix with the
shunting-yard algorithm and evaluated on a stack.
"""

_COMPARISONS = ["==", "!="]

# Higher binds tighter. `!` is unary and right-associative.
_PRECEDENCE = {
    "or": 1,
    "and": 2,
    "==": 3,
    "!=": 3,
    "!": 4,
}

def _version(value):
    value = value.strip()
    if value[:1] in ("v", "V"):
        value = value[1:]
    parts = []
    for part in value.split("."):
        if not part.isdigit():
            return None
        parts.append(int(part))
    return parts + [0] * (4 - len(parts))

_VERSION_FUNCTIONS = {
    "versionequals": lambda a, b: a == b,
    "versionnotequals": lambda a, b: a != b,
    "versiongreaterthan": lambda a, b: a > b,
    "versiongreaterthanorequals": lambda a, b: a >= b,
    "versionlessthan": lambda a, b: a < b,
    "versionlessthanorequals": lambda a, b: a <= b,
}

def _expand(text, properties):
    """Expands `$(Property)` references in a quoted string. Returns (value, error)."""
    for unsupported in ("$([", "@(", "%("):
        if unsupported in text:
            return None, "unsupported expression in '{}'".format(text)

    result = ""
    pos = 0
    for _ in range(len(text) + 1):
        start = text.find("$(", pos)
        if start == -1:
            result += text[pos:]
            break
        end = text.find(")", start)
        if end == -1:
            return None, "unterminated property in '{}'".format(text)
        result += text[pos:start] + properties.get(text[start + 2:end].lower(), "")
        pos = end + 1
    return result, None

def _call(text, properties):
    """Evaluates `[MSBuild]::Function(args)`. Returns (value, error)."""
    prefix = "[MSBuild]::"
    if not text.startswith(prefix) or not text.endswith(")"):
        return None, "unsupported property function $({})".format(text)

    name, _, args = text[len(prefix):-1].partition("(")
    function = _VERSION_FUNCTIONS.get(name.lower())
    if not function:
        return None, "unsupported property function [MSBuild]::{}".format(name)

    values = []
    for arg in args.split(","):
        arg = arg.strip()
        if len(arg) >= 2 and arg[0] == "'" and arg[-1] == "'":
            arg = arg[1:-1]
        value, error = _expand(arg, properties)
        if error:
            return None, error
        version = _version(value)
        if version == None:
            return None, "[MSBuild]::{} got {}, which is not a version".format(name, repr(value))
        values.append(version)

    if len(values) != 2:
        return None, "[MSBuild]::{} takes two arguments".format(name)

    return ("true" if function(values[0], values[1]) else "false"), None

def _matching_paren(text, open_pos):
    depth = 0
    for pos in range(open_pos, len(text)):
        if text[pos] == "(":
            depth += 1
        elif text[pos] == ")":
            depth -= 1
            if depth == 0:
                return pos
    return -1

def _tokenize(condition, properties):
    """Splits a condition into ("value", str) and ("op", str) tokens. Returns (tokens, error)."""
    tokens = []
    pos = 0
    n = len(condition)
    for _ in range(n + 1):
        if pos >= n:
            break
        char = condition[pos]
        two = condition[pos:pos + 2]
        if char in " \t\r\n":
            pos += 1
        elif char == "'":
            end = condition.find("'", pos + 1)
            if end == -1:
                return None, "unterminated string"
            value, error = _expand(condition[pos + 1:end], properties)
            if error:
                return None, error
            tokens.append(("value", value))
            pos = end + 1
        elif two == "$(":
            end = _matching_paren(condition, pos + 1)
            if end == -1:
                return None, "unterminated property"
            inner = condition[pos + 2:end]
            if inner.startswith("["):
                value, error = _call(inner, properties)
                if error:
                    return None, error
            else:
                value = properties.get(inner.lower(), "")
            tokens.append(("value", value))
            pos = end + 1
        elif two in _COMPARISONS:
            tokens.append(("op", two))
            pos += 2
        elif char in "()!":
            tokens.append(("op", char))
            pos += 1
        elif char.isalnum() or char in "._-":
            end = n
            for i in range(pos, n):
                if not (condition[i].isalnum() or condition[i] in "._-"):
                    end = i
                    break
            word = condition[pos:end]
            if word.lower() in ("and", "or"):
                tokens.append(("op", word.lower()))
            elif condition[end:].lstrip(" \t\r\n").startswith("("):
                return None, "unsupported syntax: function {}()".format(word)
            else:
                tokens.append(("value", word))
            pos = end
        else:
            return None, "unsupported syntax at {}".format(repr(condition[pos:]))
    return tokens, None

def _to_postfix(tokens):
    output = []
    operators = []
    for (kind, token) in tokens:
        if kind == "value":
            output.append((kind, token))
        elif token == "(":
            operators.append(token)
        elif token == ")":
            found = False
            for _ in range(len(operators)):
                top = operators.pop()
                if top == "(":
                    found = True
                    break
                output.append(("op", top))
            if not found:
                return None, "unbalanced parentheses"
        else:
            for _ in range(len(operators)):
                top = operators[-1]
                if top == "(" or token == "!" or _PRECEDENCE[top] < _PRECEDENCE[token]:
                    break
                output.append(("op", operators.pop()))
            operators.append(token)

    for _ in range(len(operators)):
        top = operators.pop()
        if top == "(":
            return None, "unbalanced parentheses"
        output.append(("op", top))
    return output, None

def _as_bool(value):
    if type(value) == "bool":
        return value, None
    if value.lower() == "true":
        return True, None
    if value.lower() == "false":
        return False, None
    return None, "{} is not a boolean".format(repr(value))

def evaluate_condition(condition, properties):
    """Evaluates an MSBuild condition.

    Args:
        condition: The condition, as written in the `Condition` attribute.
        properties: A dict of lower cased property name to value.

    Returns:
        A tuple of the result and an error message. The result is None if
        the condition uses something this does not support, and the error
        then says what.
    """
    tokens, error = _tokenize(condition, properties)
    if error:
        return None, error
    postfix, error = _to_postfix(tokens)
    if error:
        return None, error

    stack = []
    for (kind, token) in postfix:
        if kind == "value":
            stack.append(token)
            continue

        arity = 1 if token == "!" else 2
        if len(stack) < arity:
            return None, "malformed condition"

        if token == "!":
            value, error = _as_bool(stack.pop())
            if error:
                return None, error
            stack.append(not value)
        elif token in _COMPARISONS:
            right = stack.pop()
            left = stack.pop()
            if type(left) == "bool" or type(right) == "bool":
                return None, "comparison of a boolean expression"
            stack.append((left.lower() == right.lower()) == (token == "=="))
        else:
            right, error = _as_bool(stack.pop())
            if error:
                return None, error
            left, error = _as_bool(stack.pop())
            if error:
                return None, error
            stack.append((left and right) if token == "and" else (left or right))

    if len(stack) != 1:
        return None, "malformed condition"
    return _as_bool(stack[0])
