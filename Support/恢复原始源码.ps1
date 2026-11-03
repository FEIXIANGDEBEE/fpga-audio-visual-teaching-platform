param([ValidateSet('a','b','both')][string]$Board='both')
$ErrorActionPreference = 'Stop'
$taskRoot = $PSScriptRoot
$taskBackup = Join-Path $taskRoot 'original'
if (-not (Test-Path -LiteralPath $taskBackup)) {
    $taskBackup = 'D:\aidownload\anlu_main\aaa_comment_rework_20261103\original'
}
$taskBoards = if ($Board -eq 'both') { @('a','b') } else { @($Board) }
foreach ($taskBoard in $taskBoards) {
    $taskSource = Join-Path $taskBackup ('source\' + $taskBoard)
    $taskTarget = Join-Path $taskRoot ('source\' + $taskBoard)
    Get-ChildItem -LiteralPath $taskSource -File | Where-Object { $_.Name -notlike '*.enc.*' } | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $taskTarget $_.Name) -Force
    }
    Write-Host ('已恢复 ' + $taskBoard.ToUpper() + ' 板原始源码。加密 IP 引用保持原对象。')
}
Write-Host '原始双板位流位于备份目录 bitstream；本脚本不操作硬件。'
