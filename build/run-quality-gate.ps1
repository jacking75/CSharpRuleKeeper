param(
    [string]$Solution = "CSharpRuleKeeper.sln",
    [switch]$Fix
)

$ErrorActionPreference = "Stop"

if ($Fix)
{
    dotnet format $Solution --no-restore
}
else
{
    dotnet format $Solution --verify-no-changes --no-restore
}

if ($LASTEXITCODE -ne 0)
{
    Write-Error "서식 규칙 검사가 실패했다."
    exit $LASTEXITCODE
}

dotnet build $Solution --no-restore --configuration Debug
if ($LASTEXITCODE -ne 0)
{
    exit $LASTEXITCODE
}

dotnet test $Solution --no-build --configuration Debug
exit $LASTEXITCODE
