$out = "$env:USERPROFILE\Desktop\Host6_Logs"
$zip = "$env:USERPROFILE\Desktop\Host6_Logs.zip"

# The script must run in an elevated PowerShell session
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Error "This script must be run as Administrator. Right-click PowerShell, select 'Run as administrator', then run the script again."
}
else {
    # Remove previous output so old files cannot be included
    Remove-Item $out -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $zip -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $out -Force | Out-Null

    # Times are UTC.
    # 06:45-07:10 UTC = 13:45-14:10 on Host 6 (UTC+7),
    # covering the failure at approximately 13:55-13:57 local time.
    $q = "*[System[TimeCreated[@SystemTime>='2026-10-15T06:45:00.000Z' and @SystemTime<='2026-10-15T07:10:00.000Z']]]"

    $logs = @(
        'Microsoft-Windows-Hyper-V-VMMS-Admin',
        'Microsoft-Windows-Hyper-V-VMMS-Operational',
        'Microsoft-Windows-Hyper-V-VMMS-Networking',
        'Microsoft-Windows-Hyper-V-VmSwitch-Operational',
        'Microsoft-Windows-Hyper-V-Worker-Admin',
        'Microsoft-Windows-Hyper-V-High-Availability-Admin',
        'System'
    )

    $exported = 0
    foreach ($l in $logs) {
        $file = Join-Path $out "$l.evtx"
        wevtutil epl $l $file /q:$q /ow:true 2>$null
        if ($LASTEXITCODE -eq 0 -and (Test-Path $file)) {
            $exported++
            Write-Host "Exported: $l" -ForegroundColor Green
        }
        else {
            Write-Warning "Could not export: $l"
            Remove-Item $file -Force -ErrorAction SilentlyContinue
        }
    }

    # Collect Cluster WER reports around the failure window
    Get-ChildItem "C:\Windows\Cluster\Reports\CLUSWER_RHS_ERROR_*.evtx" -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge (Get-Date '2026-10-15 13:40') -and $_.LastWriteTime -le (Get-Date '2026-10-15 14:10') } | Copy-Item -Destination $out -Force

    # Create the ZIP only if at least one log was exported
    $collectedFiles = @(Get-ChildItem $out -File -ErrorAction SilentlyContinue)
    if ($exported -gt 0 -and $collectedFiles.Count -gt 0) {
        Compress-Archive -Path "$out\*" -DestinationPath $zip -Force
        Write-Host ""
        Write-Host "Log collection completed." -ForegroundColor Green
        Write-Host "Logs exported: $exported of $($logs.Count)"
        Write-Host "Files in ZIP: $($collectedFiles.Count)"
        Write-Host "ZIP file: $zip"
    }
    else {
        Write-Error "No logs were exported. ZIP file was not created."
    }
}
