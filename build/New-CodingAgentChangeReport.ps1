[CmdletBinding(DefaultParameterSetName = "Build")]
param(
    [Parameter(Mandatory = $true, ParameterSetName = "Build")]
    [string]$Solution,

    [Parameter(Mandatory = $true, ParameterSetName = "BuildLog")]
    [string]$BuildLogPath,

    [Parameter(Mandatory = $true, ValueFromPipeline = $true, ParameterSetName = "Pipeline")]
    [AllowEmptyString()]
    [string]$BuildOutput,

    [string]$OutputPath = "coding-agent-change-report.md",

    [string]$Target
)

begin
{
    $pipelineLines = [System.Collections.Generic.List[string]]::new()
}

process
{
    $pipelineLines.Add($BuildOutput)
}

end
{
    $ErrorActionPreference = "Stop"
    $buildExitCode = 0

    if ($PSCmdlet.ParameterSetName -eq "Build")
    {
        $buildLines = @(& dotnet build $Solution --no-restore --configuration Debug 2>&1 | ForEach-Object {
            $_.ToString()
        })
        $buildExitCode = $LASTEXITCODE
        $buildLines | ForEach-Object {
            Write-Host $_
        }
    }
    elseif ($PSCmdlet.ParameterSetName -eq "BuildLog")
    {
        $buildLines = @(Get-Content -LiteralPath $BuildLogPath)
    }
    else
    {
        $buildLines = $pipelineLines.ToArray()
    }

    if ([string]::IsNullOrWhiteSpace($Target))
    {
        if ($PSCmdlet.ParameterSetName -eq "Build")
        {
            $Target = $Solution
        }
        elseif ($PSCmdlet.ParameterSetName -eq "BuildLog")
        {
            $Target = $BuildLogPath
        }
        else
        {
            $Target = "품질 게이트 빌드 출력"
        }
    }

    $ruleGuidance = @{
        "HBCS001" = "public 필드가 외부 API, 직렬화 또는 상호 운용 계약인지 먼저 확인한다. 호환성이 안전할 때만 캡슐화된 속성으로 바꾸고, 예외가 정당하면 허용 특성을 .editorconfig에 최소 범위로 설정한다."
        "HBCS002" = "bool의 의미를 확인한 뒤 is, has, can, should, needs 중 알맞은 접두사로 이름을 변경한다. 이름 변경은 모든 참조를 함께 갱신한다."
        "HBCS003" = "컬렉션이 나타내는 복수 대상을 설명하는 복수형 이름으로 변경하고, 모든 참조를 함께 갱신한다."
        "HBCS004" = "현재 매개변수나 멤버를 가리키는 문자열인지 다시 확인한 뒤 nameof(식별자)로 바꾼다. IDE에서는 제공되는 Code Fix를 사용할 수 있다. 외부 프로토콜·JSON 키·직렬화 문자열은 바꾸지 않는다."
        "HBCS005" = "숫자의 도메인 의미를 확인한 뒤 의미 있는 const, enum 또는 지역 변수로 추출한다. 임의의 값으로 바꾸거나 허용 목록을 넓혀 진단을 숨기지 않는다."
        "HBCS006" = "동일한 책임의 코드를 private 도우미 메서드로 분리한다. 공개 API, 제어 흐름, 예외 동작과 호출 순서는 보존하고 분리 후 테스트한다."
        "HBCS007" = "타입의 책임을 기준으로 협력 타입 또는 서비스로 분리한다. 공개 API와 직렬화 계약을 바꾸지 말고, 필요한 경우 부분 클래스로 숨기기보다 책임을 실제로 분리한다."
        "HBCS008" = "멤버가 실제로 private인지 확인한 뒤 private 접근 제한자만 제거한다."
        "HBCS009" = "줄 끝 주석을 독립된 이전 줄 주석으로 옮긴다. 주석 내용과 코드 동작은 바꾸지 않는다."
        "HBCS010" = "연속된 빈 줄을 한 줄 이하로 줄인다."
        "HBCS011" = "진단 메시지의 권장 형식에 따라 int, long, uint, ulong을 각각 Int32, Int64, UInt32, UInt64로 바꾼다. 필요한 using System은 기존 관례에 맞춰 추가한다."
        "HBCS012" = "표현식의 의미를 보존하도록 인수, 조건 또는 체인을 여러 줄로 나눈다. 자동 서식 적용은 별도 승인된 -Fix 단계에서만 수행한다."
        "HBCS013" = "진단 메시지의 요구에 맞춰 인터페이스는 I 접두사, 특성은 Attribute 접미사, 추상 기반 타입은 Base 접미사, 비동기 메서드는 Async 접미사를 적용한다. 공개 계약 변경 여부를 먼저 검토한다."
        "HBCS014" = "필드 저장 방식을 확인한 뒤 인스턴스 필드는 _camelCase, static 필드는 s_camelCase, ThreadStatic 필드는 t_camelCase로 이름을 변경하고 모든 참조를 갱신한다."
        "HBCS015" = "한 파일에 섞인 책임을 기준으로 타입·기능·보조 코드로 분리한다. 단순히 줄 수를 줄이기 위해 API, 직렬화 계약 또는 코드 동작을 바꾸지 말고 분리 후 테스트한다."
    }

    $severityOrder = @{
        "error" = 0
        "warning" = 1
        "info" = 2
    }
    $diagnosticPattern = [regex]"^(?<path>.+?)\((?<line>\d+),(?<column>\d+)\):\s*(?<severity>error|warning|info)\s+(?<id>HBCS\d{3}):\s*(?<message>.*?)(?:\s+\[.*\])?$"
    $diagnostics = foreach ($buildLine in $buildLines)
    {
        $match = $diagnosticPattern.Match($buildLine)
        if (-not $match.Success)
        {
            continue
        }

        [PSCustomObject]@{
            Path = $match.Groups["path"].Value
            Line = [Int32]$match.Groups["line"].Value
            Column = [Int32]$match.Groups["column"].Value
            Severity = $match.Groups["severity"].Value
            Id = $match.Groups["id"].Value
            Message = $match.Groups["message"].Value
        }
    }

    $diagnostics = @($diagnostics |
        Sort-Object @{ Expression = { $severityOrder[$_.Severity] } }, Path, Line, Column, Id -Unique)
    $timeZone = [TimeZoneInfo]::FindSystemTimeZoneById("Korea Standard Time")
    $createdAt = [TimeZoneInfo]::ConvertTimeFromUtc([DateTime]::UtcNow, $timeZone).ToString("yyyy-MM-dd HH:mm 'KST'")
    $report = [System.Collections.Generic.List[string]]::new()
    $report.Add("# 코딩 에이전트 수정 지침")
    $report.Add("")
    $report.Add("- 생성 시각: $createdAt")
    $report.Add("- 입력: $($PSCmdlet.ParameterSetName)")
    $report.Add("- 대상: $Target")
    $report.Add("- HBCS 진단 수: $($diagnostics.Count)")
    $report.Add("")
    $report.Add("## 작업 원칙")
    $report.Add("")
    $report.Add("1. error를 먼저 처리하고, 같은 파일의 warning과 info를 함께 정리한다.")
    $report.Add("2. 각 위치의 코드를 읽어 진단 메시지와 실제 문맥이 일치하는지 확인한다.")
    $report.Add("3. 품질 게이트 통과만을 위해 public API, 직렬화 형식, 외부 프로토콜 문자열, 예외 동작을 변경하지 않는다.")
    $report.Add("4. 수정 후 같은 CSharpRuleKeeper 검사 명령을 다시 실행해 보고서를 갱신한다.")

    if ($diagnostics.Count -eq 0)
    {
        $report.Add("")
        $report.Add("## 결과")
        $report.Add("")
        $report.Add("HBCS 진단이 발견되지 않았다. 서식·컴파일·테스트까지 확인하려면 품질 게이트를 실행한다.")
    }
    else
    {
        $report.Add("")
        $report.Add("## 요약")
        $report.Add("")
        $report.Add("| 심각도 | 개수 |")
        $report.Add("| --- | ---: |")
        foreach ($severity in @("error", "warning", "info"))
        {
            $count = @($diagnostics | Where-Object Severity -eq $severity).Count
            if ($count -gt 0)
            {
                $report.Add("| $severity | $count |")
            }
        }

        foreach ($diagnostic in $diagnostics)
        {
            $report.Add("")
            $report.Add("## $($diagnostic.Id) · $($diagnostic.Severity)")
            $report.Add("")
            $report.Add("- 위치: ``$($diagnostic.Path):$($diagnostic.Line):$($diagnostic.Column)``")
            $report.Add("- 진단: $($diagnostic.Message -replace '\|', '\\|')")
            $report.Add("- 수정 방법: $($ruleGuidance[$diagnostic.Id])")
        }
    }

    $resolvedOutputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
    $outputDirectory = Split-Path -Parent $resolvedOutputPath
    if (-not (Test-Path -LiteralPath $outputDirectory))
    {
        New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    }

    Set-Content -LiteralPath $resolvedOutputPath -Value $report -Encoding utf8
    Write-Host "코딩 에이전트 수정 지침을 생성했다: $resolvedOutputPath"

    if ($PSCmdlet.ParameterSetName -eq "Build" -and $buildExitCode -ne 0)
    {
        exit $buildExitCode
    }
}
