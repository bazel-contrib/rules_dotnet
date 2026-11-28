package gazelle

// languageName is the name of this Gazelle language extension and the prefix
// of the rule kinds it generates.
const languageName = "csharp"

// typeLanguageName is the RuleIndex import language used for fully-qualified
// C# type names (e.g. "Agrifirm.Common.Tenant.Tenant").
const typeLanguageName = "csharp_type"

// namespacesKey is the private attribute under which generated csharp_library
// and csharp_binary rules carry the namespaces their sources declare, so that
// Imports can index them.
const namespacesKey = "csharp_namespaces"

// typesKey is the private attribute under which generated csharp_library and
// csharp_binary rules carry the fully-qualified type names their sources
// declare, so that Imports can index them under typeLanguageName.
const typesKey = "csharp_types"
