# SogouBlock.ps1
# Right-click -> Run as Administrator

if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")) {
    Write-Host "ERROR: Please run as Administrator!" -ForegroundColor Red
    Write-Host "Right-click the script and select 'Run as Administrator'" -ForegroundColor Yellow
    Read-Host "Press Enter to exit"
    exit
}

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "  Sogou Input Method Network Block Tool" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""

# --------------------------------------------------
# Step 1: Find Sogou installation path
# --------------------------------------------------
Write-Host "[1/6] Finding Sogou installation path..." -ForegroundColor Yellow

$sogouRoot = $null

$regPaths = @(
    "HKLM:\SOFTWARE\WOW6432Node\SogouInput",
    "HKLM:\SOFTWARE\SogouInput",
    "HKCU:\SOFTWARE\SogouInput"
)

foreach ($reg in $regPaths) {
    if (Test-Path $reg) {
        $val = (Get-ItemProperty $reg -ErrorAction SilentlyContinue).'(default)'
        if ($val -and (Test-Path $val)) {
            $sogouRoot = $val
            break
        }
    }
}

if (-not $sogouRoot) {
    $commonPaths = @(
        "C:\Program Files\SogouInput",
        "C:\Program Files (x86)\SogouInput",
        "D:\SogouInput",
        "D:\Program Files\SogouInput",
        "E:\SogouInput",
        "E:\sougou\SogouInput",
        "F:\SogouInput",
        "G:\SogouInput"
    )
    foreach ($p in $commonPaths) {
        if (Test-Path $p) {
            $sogouRoot = $p
            break
        }
    }
}

if (-not $sogouRoot) {
    Write-Host "  Searching all drives (may take 1 minute)..." -ForegroundColor Gray
    $drives = (Get-PSDrive -PSProvider FileSystem).Root
    foreach ($drive in $drives) {
        $found = Get-ChildItem $drive -Filter "SogouImeBroker.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) {
            $sogouRoot = Split-Path (Split-Path $found.FullName)
            break
        }
    }
}

if (-not $sogouRoot) {
    Write-Host "  Sogou not found. Please make sure it is installed." -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit
}

Write-Host "  Found: $sogouRoot" -ForegroundColor Green

# --------------------------------------------------
# Step 2: Enable Windows Firewall
# --------------------------------------------------
Write-Host ""
Write-Host "[2/6] Enabling Windows Firewall..." -ForegroundColor Yellow

Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\MpsSvc" -Name "Start" -Value 2 -ErrorAction SilentlyContinue
Start-Service -Name "MpsSvc" -ErrorAction SilentlyContinue

$fwRegPaths = @(
    "HKLM:\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\DomainProfile",
    "HKLM:\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\StandardProfile",
    "HKLM:\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\PublicProfile"
)
foreach ($p in $fwRegPaths) {
    Set-ItemProperty -Path $p -Name "EnableFirewall" -Value 1 -ErrorAction SilentlyContinue
}

Start-Sleep 1
Write-Host "  Firewall enabled." -ForegroundColor Green

# --------------------------------------------------
# Step 3: Block all Sogou exe via Firewall
# --------------------------------------------------
Write-Host ""
Write-Host "[3/6] Setting firewall rules..." -ForegroundColor Yellow

$fwCom = New-Object -ComObject HNetCfg.FwPolicy2
$blockedCount = 0

$allExes = Get-ChildItem -Path $sogouRoot -Recurse -Filter "*.exe" -ErrorAction SilentlyContinue

foreach ($exe in $allExes) {
    $exePath = $exe.FullName
    $exeName = $exe.BaseName

    if ($exeName -eq "SogouImeBroker") {
        continue
    }

    $rOut = New-Object -ComObject HNetCfg.FwRule
    $rOut.Name = "BLOCK_OUT_SOGOU_$exeName"
    $rOut.ApplicationName = $exePath
    $rOut.Action = 0
    $rOut.Direction = 2
    $rOut.Enabled = $true
    $rOut.Profiles = 0x7FFFFFFF

    $rIn = New-Object -ComObject HNetCfg.FwRule
    $rIn.Name = "BLOCK_IN_SOGOU_$exeName"
    $rIn.ApplicationName = $exePath
    $rIn.Action = 0
    $rIn.Direction = 1
    $rIn.Enabled = $true
    $rIn.Profiles = 0x7FFFFFFF

    $fwCom.Rules.Add($rOut)
    $fwCom.Rules.Add($rIn)
    $blockedCount++
}

Write-Host "  Firewall: blocked $blockedCount executables." -ForegroundColor Green

# --------------------------------------------------
# Step 4: Deny execute permission on dangerous exes
# --------------------------------------------------
Write-Host ""
Write-Host "[4/6] Denying execute permission on dangerous processes..." -ForegroundColor Yellow

$skipList = @("SogouImeBroker", "Uninstall")
$deniedCount = 0

foreach ($exe in $allExes) {
    $exePath = $exe.FullName
    $exeName = $exe.BaseName

    $skip = $false
    foreach ($s in $skipList) {
        if ($exeName -eq $s) {
            $skip = $true
            break
        }
    }
    if ($skip) {
        continue
    }

    Get-Process -Name $exeName -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

    $acl = Get-Acl $exePath -ErrorAction SilentlyContinue
    if ($acl) {
        $acl.SetAccessRuleProtection($true, $false)
        $deny = New-Object System.Security.AccessControl.FileSystemAccessRule("Everyone", "ExecuteFile", "Deny")
        $acl.AddAccessRule($deny)
        Set-Acl -Path $exePath -AclObject $acl -ErrorAction SilentlyContinue
        $deniedCount++
    }
}

Write-Host "  Denied execute on $deniedCount processes." -ForegroundColor Green

# --------------------------------------------------
# Step 5: Block Sogou domains via Hosts file
# --------------------------------------------------
Write-Host ""
Write-Host "[5/6] Blocking Sogou domains in Hosts file..." -ForegroundColor Yellow

$hostsPath = "C:\Windows\System32\drivers\etc\hosts"
$domains = @(
    "127.0.0.1 ime.sogou.com",
    "127.0.0.1 update.sogou.com",
    "127.0.0.1 dict.sogou.com",
    "127.0.0.1 vd.sogoucdn.com",
    "127.0.0.1 feedback.sogou.com",
    "127.0.0.1 pinyin.sogou.com",
    "127.0.0.1 stat.sogou.com",
    "127.0.0.1 log.sogou.com",
    "127.0.0.1 input.shouji.sogou.com",
    "127.0.0.1 mb.sogou.com",
    "127.0.0.1 cloud.sogou.com",
    "127.0.0.1 sync.sogou.com",
    "127.0.0.1 imeapi.sogou.com"
)

Stop-Service -Name "Dnscache" -Force -ErrorAction SilentlyContinue
Start-Sleep 1

$existing = ""
if (Test-Path $hostsPath) {
    $existing = [System.IO.File]::ReadAllText($hostsPath)
}

$toAdd = @()
foreach ($entry in $domains) {
    $domain = $entry.Split(" ")[1]
    if ($existing -notlike "*$domain*") {
        $toAdd += $entry
    }
}

if ($toAdd.Count -gt 0) {
    $newContent = $existing.TrimEnd() + "`r`n" + ($toAdd -join "`r`n") + "`r`n"
    [System.IO.File]::WriteAllText($hostsPath, $newContent, [System.Text.Encoding]::ASCII)
    Write-Host "  Added $($toAdd.Count) domain blocks." -ForegroundColor Green
} else {
    Write-Host "  Hosts entries already exist, skipped." -ForegroundColor Gray
}

Start-Service -Name "Dnscache" -ErrorAction SilentlyContinue

# --------------------------------------------------
# Step 6: Disable Sogou services and scheduled tasks
# --------------------------------------------------
Write-Host ""
Write-Host "[6/6] Disabling Sogou services and tasks..." -ForegroundColor Yellow

$svcCount = 0
$services = Get-Service | Where-Object {
    $_.DisplayName -like "*Sogou*" -or $_.Name -like "*Sogou*"
}
foreach ($svc in $services) {
    Stop-Service -Name $svc.Name -Force -ErrorAction SilentlyContinue
    Set-Service -Name $svc.Name -StartupType Disabled -ErrorAction SilentlyContinue
    $svcCount++
}

$taskCount = 0
$tasks = Get-ScheduledTask | Where-Object {
    $_.TaskName -like "*Sogou*" -or $_.TaskPath -like "*Sogou*"
}
foreach ($task in $tasks) {
    Disable-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -ErrorAction SilentlyContinue | Out-Null
    $taskCount++
}

Write-Host "  Disabled $svcCount services, $taskCount scheduled tasks." -ForegroundColor Green

# --------------------------------------------------
# Done
# --------------------------------------------------
Write-Host ""
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "  DONE! Sogou is now blocked from the internet." -ForegroundColor Cyan
Write-Host "  Typing function remains working normally." -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""

$ruleCount = ($fwCom.Rules | Where-Object { $_.Name -like "*BLOCK*SOGOU*" }).Count
$hostsCount = (Get-Content $hostsPath | Where-Object { $_ -like "*sogou*" }).Count
Write-Host "Summary:" -ForegroundColor Yellow
Write-Host "  Firewall rules : $ruleCount" -ForegroundColor White
Write-Host "  Hosts entries  : $hostsCount" -ForegroundColor White
Write-Host "  Services       : $svcCount disabled" -ForegroundColor White
Write-Host "  Tasks          : $taskCount disabled" -ForegroundColor White
Write-Host ""
Read-Host "Press Enter to exit"
