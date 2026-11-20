namespace CSharpRuleKeeper.Analyzers;

public static class RuleIds
{
    public const string PublicField = "HBCS001";
    public const string BooleanName = "HBCS002";
    public const string CollectionName = "HBCS003";
    public const string Nameof = "HBCS004";
    public const string MagicNumber = "HBCS005";
    public const string MethodLength = "HBCS006";
    public const string TypeLength = "HBCS007";
    public const string ExplicitPrivate = "HBCS008";
    public const string TrailingComment = "HBCS009";
    public const string ConsecutiveBlankLines = "HBCS010";
    public const string IntegerTypeName = "HBCS011";
    public const string LineLength = "HBCS012";
    public const string TypeNaming = "HBCS013";
    public const string FieldPrefix = "HBCS014";
    public const string FileLength = "HBCS015";

    // Configuration diagnostics are numbered from 900 so they never read as coding rules.
    public const string InvalidOption = "HBCS900";
}
