package gazelle

// languageName is the name of this Gazelle language extension and the prefix
// of the rule kinds it generates.
const languageName = "csharp"

// typeLanguageName is the RuleIndex import language used for fully-qualified
// C# type names (e.g. "Agrifirm.Common.Tenant.Tenant").
const typeLanguageName = "csharp_type"

// nsConsumerLanguageName is the RuleIndex reverse-lookup language under which
// rules index the namespaces they import or enclose, so providers with
// internal types can discover consumers during Resolve.
const nsConsumerLanguageName = "csharp_ns_consumer"

// namespacesKey is the private attribute under which generated csharp_library
// and csharp_binary rules carry the namespaces their sources declare, so that
// Imports can index them.
const namespacesKey = "csharp_namespaces"

// typesKey is the private attribute under which generated csharp_library and
// csharp_binary rules carry the fully-qualified type names their sources
// declare, so that Imports can index them under typeLanguageName.
const typesKey = "csharp_types"

// consumerInfoKey is the private attribute under which generated C# rules
// carry their consumer metadata (usings, own namespaces, referenced names)
// for reverse internals_visible_to indexing.
const consumerInfoKey = "csharp_consumer_info"
