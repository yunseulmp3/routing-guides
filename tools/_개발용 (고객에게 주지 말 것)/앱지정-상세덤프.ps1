<#
  앱별 오디오 장치 지정이 저장된 영역을 통째로 덤프한다.
  레지스트리를 읽기만 한다.
#>
param([switch]$NoPause)
$ErrorActionPreference = 'SilentlyContinue'
$out = New-Object System.Collections.Generic.List[string]
function W { param([string]$t='') Write-Host $t; $out.Add($t) | Out-Null }

function Dump-Key {
    param([string]$Path, [int]$Indent = 0, [int]$MaxLen = 220)
    $pad = ' ' * $Indent
    $item = Get-Item -Path $Path -ErrorAction SilentlyContinue
    if (-not $item) { return }
    $short = $Path -replace '^HKCU:', 'HKCU' -replace '^Microsoft\.PowerShell\.Core\\Registry::', ''
    W ("$pad[$short]")
    foreach ($n in $item.GetValueNames()) {
        $kind = $item.GetValueKind($n)
        $v = $item.GetValue($n)
        if ($v -is [byte[]]) {
            $hex = ($v | Select-Object -First 48 | ForEach-Object { $_.ToString('X2') }) -join ' '
            $txt = -join ($v | Where-Object { $_ -ge 32 -and $_ -lt 127 } | ForEach-Object { [char]$_ })
            $v = "BIN($($v.Length)) $hex" + $(if ($txt) { "   ascii='" + $txt + "'" } else { '' })
        }
        $s = [string]$v
        if ($s.Length -gt $MaxLen) { $s = $s.Substring(0, $MaxLen) + ' …' }
        $nm = if ($n) { $n } else { '(기본값)' }
        W ("$pad   $nm [$kind] = $s")
    }
}

W '===================== 앱 지정 상세 덤프 ====================='
W (" 시각: " + (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))
W ''

W '### 1. Multimedia\Audio 전체 ###'
$root = 'HKCU:\Software\Microsoft\Multimedia\Audio'
Dump-Key -Path $root
foreach ($k in (Get-ChildItem -Path $root -Recurse -ErrorAction SilentlyContinue)) {
    Dump-Key -Path $k.PSPath -Indent 2
}
W ''

W '### 2. PolicyConfig\PropertyStore 앞 15개 하위키 ###'
$ps = 'HKCU:\Software\Microsoft\Internet Explorer\LowRegistry\Audio\PolicyConfig\PropertyStore'
$subs = @(Get-ChildItem -Path $ps -ErrorAction SilentlyContinue | Select-Object -First 15)
W ("  (전체 하위키 " + @(Get-ChildItem -Path $ps -ErrorAction SilentlyContinue).Count + "개 중 15개만)")
foreach ($k in $subs) { Dump-Key -Path $k.PSPath -Indent 2 }
W ''

W '### 3. 지금 실행 중인 오디오 관련 프로세스 ###'
foreach ($p in (Get-Process -ErrorAction SilentlyContinue |
                Where-Object { $_.Path -and $_.MainWindowTitle -ne $null } |
                Sort-Object ProcessName | Select-Object -First 40)) {
    W ("  " + $p.ProcessName + "  ->  " + $p.Path)
}

$desktop = [Environment]::GetFolderPath('Desktop'); if (-not $desktop) { $desktop = $env:USERPROFILE }
$file = Join-Path $desktop ("앱지정-상세덤프_{0}.txt" -f (Get-Date).ToString('yyyyMMdd-HHmmss'))
$out -join "`r`n" | Out-File -LiteralPath $file -Encoding UTF8 -Force
Write-Host ''
Write-Host (' 결과 파일: ' + $file) -ForegroundColor Cyan
if (-not $NoPause) { Read-Host ' 엔터를 누르면 창이 닫힙니다' | Out-Null }
