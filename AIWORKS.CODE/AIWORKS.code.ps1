# ============================================================
#  AIWORKS.CODE - Local AI Agent for Windows PowerShell
#  실행: powershell -ExecutionPolicy Bypass -File AIWORKS.code.ps1
# ============================================================
#requires -Version 5.1

Set-StrictMode -Off
$ErrorActionPreference = "Stop"

# ─────────────────────────────────────────────────────────────
# [0] 전역 변수
# ─────────────────────────────────────────────────────────────
$script:Config        = @{}
$script:ChatHistory   = [System.Collections.Generic.List[hashtable]]::new()
$script:SessionActive = $true
$script:ConfigPath    = Join-Path $PSScriptRoot "AIWORKS.code.config"

# PS 5.1 호환 null 병합 헬퍼 (??  연산자 대체)
function Coalesce {
    param($Value, $Default)
    if ($null -ne $Value -and $Value -ne "") { return $Value } else { return $Default }
}

# ─────────────────────────────────────────────────────────────
# [1] 유틸리티 함수
# ─────────────────────────────────────────────────────────────

function Write-AgentLog {
    param(
        [string]$Message,
        [ValidateSet("Info","Success","Warning","Error","Thinking","Action","System")]
        [string]$Type = "Info"
    )
    $color = switch ($Type) {
        "Info"     { "Cyan"    }
        "Success"  { "Green"   }
        "Warning"  { "Yellow"  }
        "Error"    { "Red"     }
        "Thinking" { "Magenta" }
        "Action"   { "Blue"    }
        "System"   { "DarkGray"}
    }
    # ASCII 접두사 (유니코드 대체)
    $prefix = switch ($Type) {
        "Info"     { "  [*]" }
        "Success"  { "  [+]" }
        "Warning"  { "  [!]" }
        "Error"    { "  [x]" }
        "Thinking" { "  [~]" }
        "Action"   { "  [>]" }
        "System"   { "  [-]" }
    }
    if ($script:Config["ColorOutput"] -eq "true") {
        Write-Host "$prefix $Message" -ForegroundColor $color
    } else {
        Write-Host "$prefix $Message"
    }
}

function Show-Thinking {
    param([string]$Label = "Thinking")
    if ($script:Config["ShowThinking"] -ne "true") { return }
    # ASCII 스피너 (유니코드 브라유 문자 대체)
    $frames = @("|", "/", "-", "\", "|", "/", "-", "\", "|", "/", "-", "\")
    for ($i = 0; $i -lt 12; $i++) {
        $f = $frames[$i % $frames.Count]
        Write-Host "`r  $f $Label..." -NoNewline -ForegroundColor Magenta
        Start-Sleep -Milliseconds 80
    }
    Write-Host "`r                              `r" -NoNewline
}

function Request-Confirmation {
    param([string]$Message)
    Write-Host ""
    Write-Host "  [!] $Message" -ForegroundColor Yellow
    Write-Host "      계속 진행하시겠습니까? [Y/N] " -NoNewline -ForegroundColor Yellow
    $answer = Read-Host
    return ($answer -match "^[Yy]$")
}

function Write-AppLog {
    param([string]$Message, [string]$Level = "INFO")
    $logPath = $script:Config["LogPath"]
    if ($logPath -and $script:Config["LogDangerousActions"] -eq "true") {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Add-Content -Path $logPath -Value "[$timestamp][$Level] $Message" -Encoding UTF8
    }
}

# ─────────────────────────────────────────────────────────────
# [2] 설정 파일 파싱
# ─────────────────────────────────────────────────────────────

function Import-Config {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        Write-Host "  [x] 설정 파일을 찾을 수 없습니다: $Path" -ForegroundColor Red
        exit 1
    }
    $section = ""
    foreach ($line in Get-Content $Path -Encoding UTF8) {
        $line = $line.Trim()
        if ($line -match "^\[(.+)\]$") {
            $section = $matches[1]
        } elseif ($line -match "^([^#=]+)=(.*)$") {
            $key   = $matches[1].Trim()
            $value = $matches[2].Trim()
            $script:Config["$section.$key"] = $value
            $script:Config[$key]            = $value
        }
    }
    Write-AgentLog "설정 로드 완료" -Type System
}

# ─────────────────────────────────────────────────────────────
# [3] Config 파일 편집기 (AI 없이 동작)
# ─────────────────────────────────────────────────────────────

function Get-ConfigLineIndex {
    param([string[]]$Lines, [string]$Section, [string]$Key)
    $currentSection = ""
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $line = $Lines[$i].Trim()
        if ($line -match "^\[(.+)\]$") { $currentSection = $matches[1] }
        elseif ($line -match "^([^#=]+)=(.*)$") {
            if ($currentSection -eq $Section -and $matches[1].Trim() -eq $Key) { return $i }
        }
    }
    return -1
}

function Get-SectionEndIndex {
    param([string[]]$Lines, [string]$Section)
    $inSection = $false
    $lastIdx   = -1
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $line = $Lines[$i].Trim()
        if ($line -match "^\[(.+)\]$") {
            if ($inSection) { return $lastIdx }
            if ($matches[1] -eq $Section) { $inSection = $true }
        }
        if ($inSection -and $line -ne "" -and -not $line.StartsWith("#")) { $lastIdx = $i }
    }
    return $lastIdx
}

function Test-ConfigSection {
    param([string[]]$Lines, [string]$Section)
    return ($Lines | Where-Object { $_ -match "^\[$([regex]::Escape($Section))\]" }).Count -gt 0
}

function Show-ConfigList {
    param([string]$FilterSection = "")

    if (-not (Test-Path $script:ConfigPath)) {
        Write-AgentLog "Config 파일을 찾을 수 없습니다: $script:ConfigPath" -Type Error
        return
    }

    # PS 5.1: Get-Content 은 BOM 을 첫 줄에 포함 → ReadAllLines 로 BOM 자동 제거
    $rawLines = [System.IO.File]::ReadAllLines(
        $script:ConfigPath,
        [System.Text.Encoding]::UTF8
    )

    Write-Host ""
    $currentSection = ""
    $show = $true   # 현재 섹션을 출력할지 여부

    foreach ($line in $rawLines) {
        $l = $line.Trim()

        if ($l -match "^\[(.+)\]$") {
            # 섹션 헤더
            $currentSection = $matches[1]
            $show = (-not $FilterSection) -or ($currentSection -eq $FilterSection)
            if ($show) {
                Write-Host "  [$currentSection]" -ForegroundColor Yellow
            }
        } elseif ($show) {
            if ($l -eq "" -or $l.StartsWith("#")) {
                # 빈 줄 / 주석
                Write-Host "  $line" -ForegroundColor DarkGray
            } elseif ($l -match "^([^=]+)=(.*)$") {
                # 키 = 값
                $k = $matches[1].TrimEnd()
                $v = $matches[2].TrimStart()
                Write-Host "  " -NoNewline
                Write-Host $k -NoNewline -ForegroundColor Cyan
                Write-Host " = " -NoNewline -ForegroundColor DarkGray
                Write-Host $v -ForegroundColor White
            }
        }
    }
    Write-Host ""
}

function Get-ConfigValue {
    param([string]$Section, [string]$Key)
    $fullKey = "$Section.$Key"
    if ($script:Config.ContainsKey($fullKey)) {
        Write-Host ""
        Write-Host "  [$Section] $Key" -ForegroundColor Cyan
        Write-Host "  => $($script:Config[$fullKey])" -ForegroundColor White
        Write-Host ""
    } else {
        Write-AgentLog "키를 찾을 수 없습니다: [$Section] $Key" -Type Warning
    }
}

function Set-ConfigValue {
    param([string]$Section, [string]$Key, [string]$Value)
    $lines   = [System.Collections.Generic.List[string]](Get-Content $script:ConfigPath -Encoding UTF8)
    $lineIdx = Get-ConfigLineIndex -Lines $lines -Section $Section -Key $Key

    if ($lineIdx -ge 0) {
        $lines[$lineIdx] = "$Key = $Value"
        Write-AgentLog "[$Section] $Key 업데이트: $Value" -Type Success
    } else {
        if (-not (Test-ConfigSection -Lines $lines -Section $Section)) {
            $lines.Add("")
            $lines.Add("[$Section]")
            $lines.Add("$Key = $Value")
            Write-AgentLog "새 섹션 [$Section] 및 키 추가: $Key = $Value" -Type Success
        } else {
            $endIdx = Get-SectionEndIndex -Lines $lines -Section $Section
            if ($endIdx -ge 0) { $lines.Insert($endIdx + 1, "$Key = $Value") }
            else                { $lines.Add("$Key = $Value") }
            Write-AgentLog "[$Section] 새 키 추가: $Key = $Value" -Type Success
        }
    }

    Set-Content -Path $script:ConfigPath -Value $lines -Encoding UTF8
    $script:Config["$Section.$Key"] = $Value
    $script:Config[$Key]            = $Value
}

function Remove-ConfigValue {
    param([string]$Section, [string]$Key)
    $lines   = [System.Collections.Generic.List[string]](Get-Content $script:ConfigPath -Encoding UTF8)
    $lineIdx = Get-ConfigLineIndex -Lines $lines -Section $Section -Key $Key

    if ($lineIdx -ge 0) {
        $lines.RemoveAt($lineIdx)
        Set-Content -Path $script:ConfigPath -Value $lines -Encoding UTF8
        $script:Config.Remove("$Section.$Key") | Out-Null
        $script:Config.Remove($Key)            | Out-Null
        Write-AgentLog "[$Section] $Key 삭제 완료" -Type Success
    } else {
        Write-AgentLog "키를 찾을 수 없습니다: [$Section] $Key" -Type Warning
    }
}

function Add-ConfigProgram {
    param([string]$Name, [string]$ExePath)
    if (-not (Test-Path $ExePath)) {
        Write-AgentLog "경로를 찾을 수 없습니다: $ExePath" -Type Warning
        Write-Host "     경로가 존재하지 않지만 그래도 저장할까요? [Y/N] " -NoNewline -ForegroundColor Yellow
        $ans = Read-Host
        if ($ans -notmatch "^[Yy]$") { return }
    }
    Set-ConfigValue -Section "Programs" -Key $Name -Value $ExePath
    Write-AgentLog "프로그램 등록 완료: $Name => $ExePath" -Type Success
}

function Add-ConfigWarning {
    param([string]$Key, [string]$Message)
    Set-ConfigValue -Section "Warnings" -Key $Key -Value $Message

    # ConfirmKeywords에 자동 추가 (PS 5.1 호환 null 처리)
    $raw      = Coalesce $script:Config["ConfirmKeywords"] ""
    $existing = $raw -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
    if ($existing -notcontains $Key) {
        $newKeywords = ($existing + $Key) -join ","
        Set-ConfigValue -Section "Safety" -Key "ConfirmKeywords" -Value $newKeywords
        Write-AgentLog "Safety.ConfirmKeywords 에 '$Key' 자동 추가" -Type Info
    }
}

function Reload-Config {
    $script:Config.Clear()
    Import-Config -Path $script:ConfigPath
    Write-AgentLog "설정 파일 재로드 완료" -Type Success
}

function Show-ConfigHelp {
    Write-Host ""
    Write-Host "  -- /config 명령어 ------------------------------------" -ForegroundColor DarkGray
    Write-Host "  /config list                   전체 설정 출력" -ForegroundColor Yellow
    Write-Host "  /config list <섹션>             섹션별 설정 출력" -ForegroundColor Yellow
    Write-Host "  /config get <섹션> <키>         특정 값 조회" -ForegroundColor Yellow
    Write-Host "  /config set <섹션> <키> <값>    값 수정 / 추가" -ForegroundColor Yellow
    Write-Host "  /config add-program <이름> <경로>   프로그램 등록" -ForegroundColor Yellow
    Write-Host "  /config add-warning <키> <메시지>   경고 메시지 등록" -ForegroundColor Yellow
    Write-Host "  /config remove <섹션> <키>      항목 삭제" -ForegroundColor Yellow
    Write-Host "  /config reload                  파일 변경사항 즉시 반영" -ForegroundColor Yellow
    Write-Host "  ------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ""
}

function Invoke-ConfigCommand {
    param([string]$Cmd)
    $tokens = [System.Collections.Generic.List[string]]::new()
    $pattern = '"([^"]*)"|(\\S+)'
    [regex]::Matches($Cmd.Trim(), $pattern) | ForEach-Object {
        if ($_.Groups[1].Success) { $tokens.Add($_.Groups[1].Value) }
        else                      { $tokens.Add($_.Groups[2].Value) }
    }
    $sub = if ($tokens.Count -gt 1) { $tokens[1].ToLower() } else { "help" }

    switch ($sub) {
        "list" {
            $sec = if ($tokens.Count -gt 2) { $tokens[2] } else { "" }
            Show-ConfigList -FilterSection $sec
        }
        "get" {
            if ($tokens.Count -lt 4) { Write-AgentLog "사용법: /config get <섹션> <키>" -Type Warning; return }
            Get-ConfigValue -Section $tokens[2] -Key $tokens[3]
        }
        "set" {
            if ($tokens.Count -lt 5) { Write-AgentLog "사용법: /config set <섹션> <키> <값>" -Type Warning; return }
            $val = $tokens[4..($tokens.Count-1)] -join " "
            Set-ConfigValue -Section $tokens[2] -Key $tokens[3] -Value $val
        }
        "add-program" {
            if ($tokens.Count -lt 4) { Write-AgentLog "사용법: /config add-program <이름> <경로>" -Type Warning; return }
            Add-ConfigProgram -Name $tokens[2] -ExePath ($tokens[3..($tokens.Count-1)] -join " ")
        }
        "add-warning" {
            if ($tokens.Count -lt 4) { Write-AgentLog "사용법: /config add-warning <키> <메시지>" -Type Warning; return }
            Add-ConfigWarning -Key $tokens[2] -Message ($tokens[3..($tokens.Count-1)] -join " ")
        }
        "remove" {
            if ($tokens.Count -lt 4) { Write-AgentLog "사용법: /config remove <섹션> <키>" -Type Warning; return }
            Remove-ConfigValue -Section $tokens[2] -Key $tokens[3]
        }
        "reload" { Reload-Config }
        default  { Show-ConfigHelp }
    }
}

# ─────────────────────────────────────────────────────────────
# [4] AI 통신  (AI 연결 필요)
# ─────────────────────────────────────────────────────────────

function Send-AIRequest {
    param([string]$UserInput)

    $provider  = Coalesce $script:Config["Provider"] "claude"
    $endpoint  = $script:Config["Endpoint"]
    $model     = $script:Config["Model"]
    $maxTokens = [int](Coalesce $script:Config["MaxTokens"] 4096)
    $timeout   = [int](Coalesce $script:Config["TimeoutSec"] 60)
    $sysPrompt = $script:Config["SystemPrompt"]

    $script:ChatHistory.Add(@{ role = "user"; content = $UserInput })

    $maxHist = [int](Coalesce $script:Config["MaxHistory"] 20)
    while ($script:ChatHistory.Count -gt $maxHist) {
        $script:ChatHistory.RemoveAt(0)
    }

    # 히스토리 메시지 배열 (system 제외, 강제 배열 보장)
    $messages = [System.Collections.Generic.List[hashtable]]::new()
    foreach ($h in $script:ChatHistory) { $messages.Add($h) }

    # Claude API: user/assistant 교대 보장
    # 연속 동일 role 제거 (마지막 user 메시지만 남김)
    $cleaned = [System.Collections.Generic.List[hashtable]]::new()
    foreach ($m in $messages) {
        if ($cleaned.Count -gt 0 -and $cleaned[$cleaned.Count - 1].role -eq $m.role) {
            $cleaned[$cleaned.Count - 1] = $m  # 동일 role 연속 시 덮어쓰기
        } else {
            $cleaned.Add($m)
        }
    }
    $messages = $cleaned

    try {
        if ($provider -eq "claude") {
            # ── Anthropic Claude API ────────────────────────
            $apiKey  = $script:Config["ApiKey"]
            $version = Coalesce $script:Config["AnthropicVersion"] "2023-06-01"

            # ConvertTo-Json 배열 강제 보장: ,@(...) 사용
            $bodyObj = [ordered]@{
                model      = $model
                max_tokens = $maxTokens
                system     = $sysPrompt
                messages   = $messages.ToArray()
            }
            $body = $bodyObj | ConvertTo-Json -Depth 10 -Compress

            $response = Invoke-RestMethod `
                -Uri     $endpoint `
                -Method  POST `
                -Headers @{
                    "x-api-key"         = $apiKey
                    "anthropic-version" = $version
                    "content-type"      = "application/json"
                } `
                -Body       $body `
                -TimeoutSec $timeout

            # Claude 응답: response.content[0].text
            $content = $response.content[0].text

        } else {
            # ── OpenAI 호환 API (custom / openai) ──────────
            $authToken = Coalesce $script:Config["AuthToken"] ""

            $allMessages = @(@{ role = "system"; content = $sysPrompt }) + $messages
            $body = @{
                model      = $model
                messages   = $allMessages
                max_tokens = $maxTokens
            } | ConvertTo-Json -Depth 10 -Compress

            $response = Invoke-RestMethod `
                -Uri     $endpoint `
                -Method  POST `
                -Headers @{
                    "Authorization" = $authToken
                    "Content-Type"  = "application/json"
                } `
                -Body       $body `
                -TimeoutSec $timeout

            # OpenAI 응답: response.choices[0].message.content
            $content = $response.choices[0].message.content
        }

        $script:ChatHistory.Add(@{ role = "assistant"; content = $content })
        return $content
    }
    catch {
        Write-AgentLog "AI 통신 오류: $($_.Exception.Message)" -Type Error
        return $null
    }
}

function Parse-AIResponse {
    param([string]$Raw)
    try {
        $json = $Raw -replace '```json', '' -replace '```', ''
        return $json | ConvertFrom-Json
    }
    catch {
        return [PSCustomObject]@{
            action               = "answer"
            message              = $Raw
            params               = @{}
            requires_confirmation = $false
        }
    }
}

# ─────────────────────────────────────────────────────────────
# [5] 위험 작업 감지
# ─────────────────────────────────────────────────────────────

function Test-DangerousAction {
    param([string]$Input, [object]$Parsed)
    if ($Parsed.requires_confirmation -eq $true) { return $true }
    $raw      = Coalesce $script:Config["ConfirmKeywords"] ""
    $keywords = $raw -split ","
    foreach ($kw in $keywords) {
        $kw = $kw.Trim()
        if ($kw -ne "" -and $Input -match [regex]::Escape($kw)) { return $true }
    }
    return $false
}

# ─────────────────────────────────────────────────────────────
# [6] 제어 모듈
# ─────────────────────────────────────────────────────────────

function Invoke-OfficeControl {
    param([object]$Params)
    $app    = $Params.app
    $action = $Params.action
    $path   = $Params.path

    Write-AgentLog "Office 제어: [$app] $action => $path" -Type Action

    $comName = switch ($app.ToLower()) {
        "excel" { "Excel.Application"      }
        "word"  { "Word.Application"       }
        "ppt"   { "PowerPoint.Application" }
        default { throw "지원하지 않는 Office 앱: $app" }
    }

    try {
        $comApp = New-Object -ComObject $comName
        $comApp.Visible = $true
        Start-Sleep -Milliseconds ([int](Coalesce $script:Config["ComInitDelayMs"] 1500))

        switch ($action.ToLower()) {
            "open" {
                if ($app -eq "excel")      { $null = $comApp.Workbooks.Open($path) }
                elseif ($app -eq "word")   { $null = $comApp.Documents.Open($path) }
                else                       { $null = $comApp.Presentations.Open($path) }
                Write-AgentLog "파일 열기 완료: $path" -Type Success
                return "파일을 열었습니다: $path"
            }
            "read" {
                if ($app -eq "excel") {
                    $wb    = $comApp.Workbooks.Open($path)
                    $sheet = $wb.Sheets.Item(1)
                    $used  = $sheet.UsedRange
                    $data  = @()
                    for ($r = 1; $r -le [Math]::Min($used.Rows.Count, 50); $r++) {
                        $row = @()
                        for ($c = 1; $c -le $used.Columns.Count; $c++) {
                            $row += $sheet.Cells.Item($r, $c).Text
                        }
                        $data += ($row -join "`t")
                    }
                    $wb.Close($false)
                    return $data -join "`n"
                } elseif ($app -eq "word") {
                    $doc  = $comApp.Documents.Open($path)
                    $text = $doc.Content.Text
                    $doc.Close($false)
                    return $text.Substring(0, [Math]::Min($text.Length, 3000))
                }
            }
            "pdf" {
                if ($app -eq "excel") {
                    $wb      = $comApp.Workbooks.Open($path)
                    $pdfPath = [IO.Path]::ChangeExtension($path, ".pdf")
                    $wb.ExportAsFixedFormat(0, $pdfPath)
                    $wb.Close($false)
                    Write-AgentLog "PDF 변환 완료: $pdfPath" -Type Success
                    return "PDF 저장: $pdfPath"
                } elseif ($app -eq "word") {
                    $doc     = $comApp.Documents.Open($path)
                    $pdfPath = [IO.Path]::ChangeExtension($path, ".pdf")
                    $doc.SaveAs([ref]$pdfPath, [ref]17)
                    $doc.Close($false)
                    return "PDF 저장: $pdfPath"
                }
            }
        }
    }
    catch {
        Write-AgentLog "Office 제어 오류: $($_.Exception.Message)" -Type Error
        return "오류: $($_.Exception.Message)"
    }
    finally {
        try { if ($comApp) { $comApp.Quit() } } catch {}
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($comApp) | Out-Null
    }
}

function Invoke-HwpControl {
    param([object]$Params)
    $action = $Params.action
    $path   = $Params.path

    Write-AgentLog "한글(HWP) 제어: $action => $path" -Type Action

    try {
        $hwp     = New-Object -ComObject "HWPFrame.HwpObject"
        $secPath = $script:Config["HwpSecurityPath"]
        if ($secPath) {
            $hwp.XHwpDocuments.RegisterModule("FilePathCheckDLL", $secPath)
        }
        $hwp.XHwpWindows.Active_XHwpWindow.Visible = $true

        switch ($action.ToLower()) {
            "open" {
                $hwp.Open($path, "HWP", "forceopen:true")
                Write-AgentLog "HWP 열기 완료" -Type Success
                return "HWP 파일 열기: $path"
            }
            "read" {
                $hwp.Open($path, "HWP", "forceopen:true")
                $text = $hwp.GetTextFile("TEXT", "")
                $hwp.Quit()
                return $text.Substring(0, [Math]::Min($text.Length, 3000))
            }
            "close" {
                $hwp.Quit()
                return "HWP 종료"
            }
        }
    }
    catch {
        Write-AgentLog "HWP 제어 오류: $($_.Exception.Message)" -Type Error
        return "오류: $($_.Exception.Message)"
    }
}

function Invoke-IEControl {
    param([object]$Params)
    $action   = $Params.action
    $url      = $Params.url
    $selector = $Params.selector
    $value    = $Params.value

    Write-AgentLog "IE 제어: $action => $url" -Type Action

    try {
        $ie = New-Object -ComObject "InternetExplorer.Application"
        $ie.Visible = $true

        switch ($action.ToLower()) {
            "open" {
                $ie.Navigate($url)
                while ($ie.Busy) { Start-Sleep -Milliseconds 200 }
                Write-AgentLog "IE 페이지 로드 완료: $url" -Type Success
                return "IE 열기: $url"
            }
            "read" {
                $ie.Navigate($url)
                while ($ie.Busy) { Start-Sleep -Milliseconds 200 }
                $body = $ie.Document.Body.InnerText
                return $body.Substring(0, [Math]::Min($body.Length, 3000))
            }
            "input" {
                $el = $ie.Document.getElementById($selector)
                if ($el) { $el.value = $value; return "입력 완료" }
                else     { return "요소를 찾을 수 없음: $selector" }
            }
            "click" {
                $el = $ie.Document.getElementById($selector)
                if ($el) { $el.click(); return "클릭 완료" }
                else     { return "요소를 찾을 수 없음: $selector" }
            }
            "close" {
                $ie.Quit()
                [System.Runtime.InteropServices.Marshal]::ReleaseComObject($ie) | Out-Null
                return "IE 종료"
            }
        }
    }
    catch {
        Write-AgentLog "IE 제어 오류: $($_.Exception.Message)" -Type Error
        return "오류: $($_.Exception.Message)"
    }
}

function Invoke-ChromeControl {
    param([object]$Params)
    $action      = $Params.action
    $url         = $Params.url
    $script_code = $Params.script

    Write-AgentLog "Chrome 제어: $action => $url" -Type Action

    switch ($action.ToLower()) {
        "open" {
            $chromePath = $script:Config["ChromeExePath"]
            if ($chromePath -and (Test-Path $chromePath)) {
                Start-Process $chromePath -ArgumentList $url
            } else {
                Start-Process "chrome" -ArgumentList $url
            }
            return "Chrome 열기: $url"
        }
        "script" {
            $tempScript = [IO.Path]::GetTempFileName() + ".js"
            $jsCode = @"
const { chromium } = require('playwright');
(async () => {
    const browser = await chromium.launch({ headless: false });
    const page = await browser.newPage();
    await page.goto('$url');
    $script_code
    await browser.close();
})();
"@
            Set-Content -Path $tempScript -Value $jsCode -Encoding UTF8
            $result = & node $tempScript 2>&1
            Remove-Item $tempScript -ErrorAction SilentlyContinue
            return $result -join "`n"
        }
    }
}

function Invoke-PdfControl {
    param([object]$Params)
    $path = $Params.path

    Write-AgentLog "PDF 추출: $path" -Type Action

    $tool     = Coalesce $script:Config["PdfExtractTool"] "pdftotext"
    $toolPath = $script:Config["PdfToolPath"]
    $exe      = if ($toolPath -and $toolPath -ne "") { $toolPath } else { $tool }
    $outFile  = [IO.Path]::GetTempFileName()

    try {
        & $exe $path $outFile 2>&1 | Out-Null
        if (Test-Path $outFile) {
            $text = Get-Content $outFile -Raw -Encoding UTF8
            Remove-Item $outFile -ErrorAction SilentlyContinue
            return $text.Substring(0, [Math]::Min($text.Length, 3000))
        }
        return "PDF 텍스트 추출 실패"
    }
    catch {
        Write-AgentLog "PDF 오류: $($_.Exception.Message)" -Type Error
        return "오류: $($_.Exception.Message)"
    }
}

# ─────────────────────────────────────────────────────────────
# [7] 작업 디스패처
# ─────────────────────────────────────────────────────────────

function Invoke-AgentAction {
    param([string]$UserInput, [object]$Parsed)

    $action = $Parsed.action
    $params = $Parsed.params
    $msg    = $Parsed.message

    if (Test-DangerousAction -Input $UserInput -Parsed $Parsed) {
        $confirmed = Request-Confirmation -Message $msg
        if (-not $confirmed) {
            Write-AgentLog "작업이 취소되었습니다." -Type Warning
            Write-AppLog "사용자 거부: $action / $UserInput" -Level "WARN"
            return
        }
        Write-AppLog "사용자 승인: $action / $UserInput" -Level "INFO"
    }

    if ($msg) { Write-AgentLog $msg -Type Thinking }

    $result = switch ($action) {
        "office" { Invoke-OfficeControl -Params $params }
        "hwp"    { Invoke-HwpControl    -Params $params }
        "ie"     { Invoke-IEControl     -Params $params }
        "chrome" { Invoke-ChromeControl -Params $params }
        "pdf"    { Invoke-PdfControl    -Params $params }
        "shell"  {
            $cmd = $params.command
            Write-AgentLog "Shell 실행: $cmd" -Type Action
            Invoke-Expression $cmd 2>&1
        }
        "answer" {
            Write-Host ""
            Write-Host "  $msg" -ForegroundColor White
            Write-Host ""
            return
        }
        default {
            Write-AgentLog "알 수 없는 action: $action" -Type Warning
            return
        }
    }

    if ($result) {
        Write-Host ""
        Write-Host "  [결과]" -ForegroundColor DarkGray
        Write-Host "  $result" -ForegroundColor White
        Write-Host ""
        # Claude API: user 다음은 반드시 assistant 역할
        $script:ChatHistory.Add(@{
            role    = "assistant"
            content = "[SYSTEM] 작업 결과: $result"
        })
    }
}

# ─────────────────────────────────────────────────────────────
# [8] 슬래시 명령어 처리
# ─────────────────────────────────────────────────────────────

function Invoke-SlashCommand {
    param([string]$Cmd)

    switch -Regex ($Cmd.Trim()) {
        "^/exit$" {
            Write-AgentLog "AIWORKS 세션을 종료합니다." -Type System
            $script:SessionActive = $false
            return $true
        }
        "^/clear$" {
            Clear-Host
            Show-Banner
            return $true
        }
        "^/status$" {
            Write-Host ""
            Write-Host "  -- 세션 상태 ----------------------------------" -ForegroundColor DarkGray
            Write-Host "  대화 히스토리 : $($script:ChatHistory.Count) 건" -ForegroundColor Cyan
            Write-Host "  AI 엔드포인트 : $($script:Config["Endpoint"])"   -ForegroundColor Cyan
            Write-Host "  모델          : $($script:Config["Model"])"       -ForegroundColor Cyan
            Write-Host "  -----------------------------------------------" -ForegroundColor DarkGray
            Write-Host ""
            return $true
        }
        "^/history$" {
            Write-Host ""
            if ($script:ChatHistory.Count -eq 0) {
                Write-AgentLog "대화 히스토리가 없습니다." -Type System
            } else {
                foreach ($h in $script:ChatHistory) {
                    $color = if ($h.role -eq "user") { "Cyan" } else { "White" }
                    $preview = $h.content.Substring(0, [Math]::Min($h.content.Length, 100))
                    Write-Host "  [$($h.role.ToUpper())] $preview" -ForegroundColor $color
                }
            }
            Write-Host ""
            return $true
        }
        "^/reset$" {
            $script:ChatHistory.Clear()
            Write-AgentLog "대화 히스토리를 초기화했습니다." -Type Success
            return $true
        }
        "^/config" {
            Invoke-ConfigCommand -Cmd $Cmd
            return $true
        }
        "^/help$" {
            Write-Host ""
            Write-Host "  -- 사용 가능한 명령어 -------------------------" -ForegroundColor DarkGray
            Write-Host "  /exit              세션 종료"                    -ForegroundColor Yellow
            Write-Host "  /clear             화면 초기화"                  -ForegroundColor Yellow
            Write-Host "  /status            현재 세션 상태 출력"          -ForegroundColor Yellow
            Write-Host "  /history           대화 히스토리 출력"           -ForegroundColor Yellow
            Write-Host "  /reset             대화 히스토리 초기화"         -ForegroundColor Yellow
            Write-Host "  /config [서브커맨드]  설정 파일 편집 (AI 불필요)" -ForegroundColor Yellow
            Write-Host "  /help              이 도움말 출력"               -ForegroundColor Yellow
            Write-Host ""
            Write-Host "  /config 세부 명령어는 /config help 참고"        -ForegroundColor DarkGray
            Write-Host "  -----------------------------------------------" -ForegroundColor DarkGray
            Write-Host ""
            return $true
        }
    }
    return $false
}

# ─────────────────────────────────────────────────────────────
# [9] 배너 출력
# ─────────────────────────────────────────────────────────────

function Show-Banner {
    Write-Host ""
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |     A I W O R K S . C O D E             |" -ForegroundColor Cyan
    Write-Host "  |     Local AI Agent for Windows PS        |" -ForegroundColor DarkCyan
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host "  /help 로 명령어 목록 확인  |  /exit 로 종료"  -ForegroundColor DarkGray
    Write-Host ""
}

# ─────────────────────────────────────────────────────────────
# [10] 메인 REPL 루프
# ─────────────────────────────────────────────────────────────

function Start-AgentREPL {
    Import-Config -Path $script:ConfigPath
    Clear-Host
    Show-Banner

    Write-AgentLog "AI 엔드포인트: $($script:Config["Endpoint"])" -Type System
    Write-AgentLog "세션 시작. 자연어로 명령을 입력하세요." -Type System
    Write-Host ""

    $promptLabel = Coalesce $script:Config["Prompt"] "AIWORKS"

    while ($script:SessionActive) {
        Write-Host "  $promptLabel> " -NoNewline -ForegroundColor Green
        $userInput = Read-Host

        if ([string]::IsNullOrWhiteSpace($userInput)) { continue }

        if ($userInput.StartsWith("/")) {
            $handled = Invoke-SlashCommand -Cmd $userInput
            if (-not $handled) {
                Write-AgentLog "알 수 없는 명령어입니다. /help 를 입력하세요." -Type Warning
            }
            continue
        }

        Write-Host ""
        Show-Thinking -Label "AI 처리 중"

        $raw = Send-AIRequest -UserInput $userInput
        if (-not $raw) { continue }

        $parsed = Parse-AIResponse -Raw $raw
        Invoke-AgentAction -UserInput $userInput -Parsed $parsed
    }

    Write-Host ""
    Write-Host "  AIWORKS 세션 종료." -ForegroundColor DarkGray
    Write-Host ""
}

# ─────────────────────────────────────────────────────────────
# 엔트리포인트
# ─────────────────────────────────────────────────────────────
Start-AgentREPL
