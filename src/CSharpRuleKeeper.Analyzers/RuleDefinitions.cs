using Microsoft.CodeAnalysis;

namespace CSharpRuleKeeper.Analyzers;

static class RuleDefinitions
{
    const string DesignCategory = "Design";
    const string MaintainabilityCategory = "Maintainability";
    const string NamingCategory = "Naming";
    const string StyleCategory = "Style";
    const string HelpLinkBase = "https://github.com/jacking75/CSharpRuleKeeper/blob/main/docs/RULES.md";

    internal static readonly DiagnosticDescriptor s_publicField = Create(
        RuleIds.PublicField,
        "Public fields are not allowed",
        "Public field '{0}' must be replaced or explicitly excepted",
        DesignCategory,
        DiagnosticSeverity.Error);

    internal static readonly DiagnosticDescriptor s_booleanName = Create(
        RuleIds.BooleanName,
        "Boolean names must express a state",
        "Boolean {0} '{1}' must start with one of: {2}",
        NamingCategory,
        DiagnosticSeverity.Warning);

    internal static readonly DiagnosticDescriptor s_collectionName = Create(
        RuleIds.CollectionName,
        "Collection names should be plural",
        "Collection {0} '{1}' should use a plural name",
        NamingCategory,
        DiagnosticSeverity.Warning);

    internal static readonly DiagnosticDescriptor s_nameof = Create(
        RuleIds.Nameof,
        "Use nameof for known identifiers",
        "String literal '{0}' refers to a known {1}; use nameof",
        DesignCategory,
        DiagnosticSeverity.Warning);

    internal static readonly DiagnosticDescriptor s_magicNumber = Create(
        RuleIds.MagicNumber,
        "Avoid magic numbers",
        "Numeric literal '{0}' should be extracted to a named constant, enum, or variable",
        MaintainabilityCategory,
        DiagnosticSeverity.Warning);

    internal static readonly DiagnosticDescriptor s_methodLengthWarning = Create(
        RuleIds.MethodLength,
        "Method is a refactoring candidate",
        "Method '{0}' has {1} physical lines and exceeds the warning limit of {2}",
        MaintainabilityCategory,
        DiagnosticSeverity.Warning);

    internal static readonly DiagnosticDescriptor s_methodLengthError = Create(
        RuleIds.MethodLength,
        "Method is too long",
        "Method '{0}' has {1} physical lines and exceeds the maximum of {2}",
        MaintainabilityCategory,
        DiagnosticSeverity.Error);

    internal static readonly DiagnosticDescriptor s_typeLengthWarning = Create(
        RuleIds.TypeLength,
        "Type is a refactoring candidate",
        "Type '{0}' has {1} physical lines and exceeds the warning limit of {2}",
        MaintainabilityCategory,
        DiagnosticSeverity.Warning);

    internal static readonly DiagnosticDescriptor s_typeLengthError = Create(
        RuleIds.TypeLength,
        "Type is too long",
        "Type '{0}' has {1} physical lines and exceeds the maximum of {2}",
        MaintainabilityCategory,
        DiagnosticSeverity.Error);

    internal static readonly DiagnosticDescriptor s_fileLengthWarning = Create(
        RuleIds.FileLength,
        "Source file is a refactoring candidate",
        "Source file has {0} physical lines and exceeds the warning limit of {1}",
        MaintainabilityCategory,
        DiagnosticSeverity.Warning);

    internal static readonly DiagnosticDescriptor s_fileLengthError = Create(
        RuleIds.FileLength,
        "Source file is too long",
        "Source file has {0} physical lines and exceeds the maximum of {1}",
        MaintainabilityCategory,
        DiagnosticSeverity.Error);

    internal static readonly DiagnosticDescriptor s_explicitPrivate = Create(
        RuleIds.ExplicitPrivate,
        "Omit the private modifier",
        "Private modifier on {0} '{1}' should be omitted",
        StyleCategory,
        DiagnosticSeverity.Info);

    internal static readonly DiagnosticDescriptor s_trailingComment = Create(
        RuleIds.TrailingComment,
        "Place comments on their own line",
        "Trailing comment must be moved to its own line",
        StyleCategory,
        DiagnosticSeverity.Warning);

    internal static readonly DiagnosticDescriptor s_consecutiveBlankLines = Create(
        RuleIds.ConsecutiveBlankLines,
        "Avoid consecutive blank lines",
        "Only one consecutive blank line is allowed",
        StyleCategory,
        DiagnosticSeverity.Warning);

    internal static readonly DiagnosticDescriptor s_integerTypeName = Create(
        RuleIds.IntegerTypeName,
        "Use explicit-width integer type names",
        "Use '{0}' instead of the '{1}' keyword",
        StyleCategory,
        DiagnosticSeverity.Warning);

    internal static readonly DiagnosticDescriptor s_lineLength = Create(
        RuleIds.LineLength,
        "Line is too long",
        "Line has {0} characters and exceeds the configured maximum of {1}",
        StyleCategory,
        DiagnosticSeverity.Warning);

    internal static readonly DiagnosticDescriptor s_typeNaming = Create(
        RuleIds.TypeNaming,
        "Type name does not follow the required pattern",
        "{0} '{1}' must {2}",
        NamingCategory,
        DiagnosticSeverity.Warning);

    internal static readonly DiagnosticDescriptor s_fieldPrefix = Create(
        RuleIds.FieldPrefix,
        "Field prefix does not match its storage kind",
        "Field '{0}' must use the '{1}' prefix followed by a camelCase name",
        NamingCategory,
        DiagnosticSeverity.Error);

    static DiagnosticDescriptor Create(
        string id,
        string title,
        string messageFormat,
        string category,
        DiagnosticSeverity severity)
    {
        return new DiagnosticDescriptor(
            id,
            title,
            messageFormat,
            category,
            severity,
            isEnabledByDefault: true,
            helpLinkUri: $"{HelpLinkBase}#{id.ToLowerInvariant()}");
    }
}
