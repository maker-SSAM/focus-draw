# 소개 그림 일곱 장과 GitHub 썸네일을 다시 뽑는다.
#   PowerShell에서:  powershell -ExecutionPolicy Bypass -File 소개자료\build.ps1          (전부)
#                    powershell -ExecutionPolicy Bypass -File 소개자료\build.ps1 1 og     (몇 장만)
# Windows에 늘 있는 PowerShell과 Edge만 쓴다(예전 build.py는 파이썬이 없는 PC에서 돌지 않았다).
#
# slides.html의 {{파일이름}} 자리에 그림을 data URI로 끼워 넣은 뒤(Edge는 file:// 그림을 CSS 마스크로
# 쓰지 못한다), Edge 헤드리스로 장마다 PNG를 찍는다. 그림은 이 폴더에서 먼저, 없으면 상위(프로젝트)
# 폴더에서 찾는다. {{?파일이름}}은 "있으면 쓰는" 자리다 — 없으면 빈칸이 된다.
#   1장(표지)과 썸네일의 칠판 화면: 이 폴더의 "1번-화면.png"(또는 .jpg) — 제작자가 직접 시연하고 캡처한 그림.
#   5장의 단축키 그림: 프로젝트 폴더의 shortcuts.png (설정 창이 띄우는 것과 같은 그림)

$ErrorActionPreference = 'Stop'
$here  = $PSScriptRoot
$root  = Split-Path $here
$edge  = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
$scale = '1.5'  # 1600x900 → 2400x1350. 메신저로 보내도 글씨가 또렷하게
$names = @('01-소개', '02-두-프로그램을-하나로', '03-위젯', '04-개인화', '05-단축키', '06-전자칠판', '07-시작하기')

function Find-Picture($name) {
    $stem = [IO.Path]::GetFileNameWithoutExtension($name)
    foreach ($folder in $here, $root) {
        foreach ($cand in $name, "$stem.jpg", "$stem.jpeg") {
            $p = Join-Path $folder $cand
            if (Test-Path -LiteralPath $p) { return $p }
        }
    }
    return $null
}

$utf8 = New-Object Text.UTF8Encoding($false)
$html = [IO.File]::ReadAllText((Join-Path $here 'slides.html'), $utf8)
$html = [regex]::Replace($html, '\{\{(\??)([^}]+\.png)\}\}', {
    param($m)
    $optional = $m.Groups[1].Value -eq '?'
    $path = Find-Picture $m.Groups[2].Value
    if (-not $path) {
        if ($optional) { return '' }
        throw "그림을 찾을 수 없음: $($m.Groups[2].Value)"
    }
    $mime = if ($path -match '\.jpe?g$') { 'image/jpeg' } else { 'image/png' }
    return "data:$mime;base64," + [Convert]::ToBase64String([IO.File]::ReadAllBytes($path))
})
$built = Join-Path ([IO.Path]::GetTempPath()) 'focus-draw-slides.html'
[IO.File]::WriteAllText($built, $html, $utf8)

$only = if ($args.Count) { $args } else { @(1..$names.Count) + 'og' }
foreach ($arg in $only) {
    if ("$arg" -eq 'og') {  # GitHub 링크 썸네일 (Settings → Social preview). 권장 1280x640, 1MB 이하
        $out = Join-Path $here 'github-social-preview.png'; $size = '1280,640'; $s = '1'
    } else {
        $out = Join-Path $here ($names[[int]$arg - 1] + '.png'); $size = '1600,900'; $s = $scale
    }
    $url = 'file:///' + ($built -replace '\\', '/') + "#$arg"
    $p = Start-Process -FilePath $edge -Wait -PassThru -WindowStyle Hidden -ArgumentList @(
        '--headless=new', '--disable-gpu', '--hide-scrollbars', '--virtual-time-budget=3000',
        "--force-device-scale-factor=$s", '--default-background-color=FFFFFFFF', "--window-size=$size",
        "`"--screenshot=$out`"", "`"$url`"")
    if ($p.ExitCode -ne 0) { throw "Edge가 실패함 ($arg)" }
    $out
}
