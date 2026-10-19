package gazelle

// languageName is the name of this Gazelle language extension and the prefix
// of the rule kinds it generates.
const languageName = "csharp"

// namespacesKey is the private attribute under which generated csharp_library
// and csharp_binary rules carry the namespaces their sources declare, so that
// Imports can index them.
const namespacesKey = "csharp_namespaces"
