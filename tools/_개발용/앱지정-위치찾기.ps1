<#
  윈도우가 "앱별 오디오 장치 지정"을 어디에 저장하는지 찾는 탐색 도구.
  레지스트리를 읽기만 합니다. 아무것도 바꾸지 않습니다.
#>
param([switch]$NoPause)

$ErrorActionPreference = 'SilentlyContinue'
$out = New-Object System.Collections.Generic.List[string]
function W { param([string]$t = '', [string]$c = 'Gray') Write-Host $t -ForegroundColor $c; $out.Add($t) | Out-Null }

W '=====================================================================' 'DarkGray'
W ' 앱별 오디오 장치 지정 - 저장 위치 탐색' 'Cyan'
W (" 시각: " + (Get-Date).ToString('yyyy-MM-dd HH:mm:ss') + "  /  " + [System.Environment]::OSVersion.VersionString) 'DarkGray'
W '=====================================================================' 'DarkGray'
W ''

# 1) 알려진 후보 경로 존재 확인
$known = @(
  'HKCU:\Software\Microsoft\Internet Explorer\LowRegistry\Audio\PolicyConfig\PropertyStore',
  'HKCU:\Software\Microsoft\Multimedia\Audio',
  'HKCU:\Software\Microsoft\Multimedia\Audio\DefaultDeviceAssociation',
  'HKCU:\Software\Microsoft\Windows\CurrentVersion\Audio',
  'HKCU:\Software\Microsoft\Windows\CurrentVersion\MMDevices'
)
W '[1] 알려진 후보 경로' 'Yellow'
foreach ($p in $known) {
    if (Test-Path $p) {
        $n = @(Get-ChildItem -Path $p -ErrorAction SilentlyContinue).Count
        $v = @((Get-Item -Path $p).GetValueNames()).Count
        W ("  있음   " + $p + "   (하위키 $n / 값 $v)") 'Green'
    } else {
        W ("  없음   " + $p) 'DarkGray'
    }
}
W ''

# 2) 엔드포인트 ID 문자열을 담은 값을 찾아 훑기
$roots = @(
  'HKCU:\Software\Microsoft\Internet Explorer\LowRegistry',
  'HKCU:\Software\Microsoft\Multimedia',
  'HKCU:\Software\Microsoft\Windows\CurrentVersion',
  'HKCU:\Software\Microsoft\Windows NT\CurrentVersion',
  'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel'
)
W '[2] 엔드포인트 ID를 담은 레지스트리 값 검색' 'Yellow'
W '    (최대 120초. 화면이 멈춘 것처럼 보여도 정상입니다)' 'DarkGray'
W ''

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$hits = 0
$scanned = 0
foreach ($root in $roots) {
    if (-not (Test-Path $root)) { continue }
    $keys = @(Get-ChildItem -Path $root -Recurse -ErrorAction SilentlyContinue)
    foreach ($k in $keys) {
        if ($sw.Elapsed.TotalSeconds -gt 120) { W '  [시간 초과 - 검색 중단]' 'Yellow'; break }
        $scanned++
        $item = Get-Item -Path $k.PSPath -ErrorAction SilentlyContinue
        if (-not $item) { continue }
        foreach ($name in $item.GetValueNames()) {
            $val = $item.GetValue($name)
            if ($val -isnot [string]) { continue }
            if ($val -notlike '*{0.0.*') { continue }
            $hits++
            if ($hits -le 60) {
                $short = $val
                if ($short.Length -gt 180) { $short = $short.Substring(0, 180) + ' …' }
                $vn = if ($name) { $name } else { '(기본값)' }
                W ("  ► " + $k.PSPath.Replace('Microsoft.PowerShell.Core\Registry::', '')) 'White'
                W ("      " + $vn + " = " + $short) 'Gray'
            }
        }
    }
    if ($sw.Elapsed.TotalSeconds -gt 120) { break }
}
W ''
W ("  검색한 키 $scanned 개 / 찾은 값 $hits 개 / 소요 " + [math]::Round($sw.Elapsed.TotalSeconds,1) + "초") 'Cyan'
if ($hits -gt 60) { W ("  (화면에는 60개까지만 표시했습니다)") 'DarkGray' }
W ''

$desktop = [Environment]::GetFolderPath('Desktop')
if (-not $desktop) { $desktop = $env:USERPROFILE }
$file = Join-Path $desktop ("앱지정-위치찾기_{0}.txt" -f (Get-Date).ToString('yyyyMMdd-HHmmss'))
$out -join "`r`n" | Out-File -LiteralPath $file -Encoding UTF8 -Force
Write-Host ' 결과 파일:' -ForegroundColor Cyan
Write-Host ("   " + $file) -ForegroundColor White
Write-Host ''
if (-not $NoPause) { Read-Host ' 엔터를 누르면 창이 닫힙니다' | Out-Null }
