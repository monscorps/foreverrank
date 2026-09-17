# ForeverProbe Sync: ships your ForeverProbe data to the guild automatically.
#
# What it does, in full: finds ForeverProbeDB.lua under your WoW beta's
# SavedVariables and, when the file changes (WoW writes it at logout and on
# /reload), posts it to the guild's private Discord webhook. Nothing else is
# read, nothing runs inside the game, and you can read every line below.
#
# Install:   ForeverProbe Setup.exe or Install.bat (or: .\ForeverProbe-Sync.ps1 -Install)
# Running:   the sigil sits in your system tray and syncs every 30 minutes;
#            right-click it for Sync now / Status / Exit. Returns at login.
# Remove:    double-click Uninstall.bat (or: -Uninstall)

param(
  [switch]$Install,
  [switch]$Uninstall,
  [switch]$Status,
  [switch]$SyncNow,
  [switch]$Tray,
  [string]$WowPath = ""
)

$AppDir   = Join-Path $env:APPDATA "ForeverProbe"
$CfgFile  = Join-Path $AppDir "config.json"
$LogFile  = Join-Path $AppDir "sync.log"
$TaskName = "ForeverProbe Sync"   # older builds ran as a scheduled task

function Log([string]$msg) {
  $line = (Get-Date -Format "yyyy-MM-dd HH:mm:ss") + "  " + $msg
  Add-Content -Path $LogFile -Value $line -ErrorAction SilentlyContinue
}

function Find-SavedVariables {
  param([string]$Root)
  $roots = @()
  if ($Root) { $roots += $Root }
  $roots += @("C:\Program Files (x86)\World of Warcraft", "C:\Program Files\World of Warcraft", "D:\World of Warcraft", "$env:USERPROFILE\World of Warcraft")
  foreach ($r in $roots) {
    foreach ($flavor in @("_beta_", "_ptr_", "_retail_")) {
      $acct = Join-Path (Join-Path $r $flavor) "WTF\Account"
      if (Test-Path $acct) {
        Get-ChildItem -Path $acct -Recurse -Filter "ForeverProbeDB.lua" -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }
      }
    }
  }
}

function Send-ToWebhook {
  param([string]$Webhook, [string]$File, [string]$Mark)
  $boundary = [System.Guid]::NewGuid().ToString()
  $LF = "`r`n"
  $bytes = [System.IO.File]::ReadAllBytes($File)
  $enc = [System.Text.Encoding]::GetEncoding("ISO-8859-1")
  $who = $env:USERNAME
  $tag = ""
  if ($Mark) { $tag = "[" + $Mark + "] " }
  $pre = "--$boundary$LF" +
    "Content-Disposition: form-data; name=`"payload_json`"$LF$LF" +
    ('{"content":"' + $tag + 'ForeverProbe drop from **' + $who + '**, ' + (Get-Date -Format "yyyy-MM-dd HH:mm") + '"}') + $LF +
    "--$boundary$LF" +
    "Content-Disposition: form-data; name=`"file`"; filename=`"ForeverProbeDB.lua`"$LF" +
    "Content-Type: application/octet-stream$LF$LF"
  $post = "$LF--$boundary--$LF"
  $body = $enc.GetBytes($pre) + $bytes + $enc.GetBytes($post)
  Invoke-RestMethod -Uri $Webhook -Method Post -ContentType "multipart/form-data; boundary=$boundary" -Body $body | Out-Null
}

function Run-Sync {
  if (-not (Test-Path $CfgFile)) { return "Not installed." }
  $cfg = Get-Content $CfgFile -Raw | ConvertFrom-Json
  $sentHashes = @{}
  if ($cfg.sent) { $cfg.sent.PSObject.Properties | ForEach-Object { $sentHashes[$_.Name] = $_.Value } }
  $files = @(Find-SavedVariables -Root $cfg.wowPath)
  if ($files.Count -eq 0) { Log "no ForeverProbeDB.lua found"; return "No ForeverProbe data found yet. Log a character out once with the addon installed." }
  $posted = 0; $skipped = 0; $failed = 0
  foreach ($f in $files) {
    $hash = (Get-FileHash -Path $f -Algorithm SHA256).Hash
    if ($sentHashes[$f] -eq $hash) { $skipped++; continue }
    try {
      Send-ToWebhook -Webhook $cfg.webhook -File $f -Mark $cfg.mark
      $sentHashes[$f] = $hash
      $posted++
      Log ("sent " + $f)
    } catch {
      $failed++
      Log ("FAILED " + $f + " :: " + $_.Exception.Message)
    }
  }
  $cfg.sent = $sentHashes
  $cfg | ConvertTo-Json | Set-Content -Path $CfgFile
  if ($failed -gt 0) { return "Sent $posted, failed $failed. See sync.log in $AppDir." }
  if ($posted -gt 0) { return "Sent $posted update(s) to the guild." }
  return "Everything already sent. Nothing new since your last session."
}

function Stop-Tray {
  # Ends any running tray instance (an older build's included) so install and
  # uninstall never leave a stale sigil behind.
  try {
    Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
      Where-Object { $_.CommandLine -match "ForeverProbe-Sync" -and $_.CommandLine -match "-Tray" -and $_.ProcessId -ne $PID } |
      ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
  } catch { }
}

function Show-Status {
  Add-Type -AssemblyName System.Windows.Forms | Out-Null
  if (-not (Test-Path $CfgFile)) {
    [System.Windows.Forms.MessageBox]::Show("ForeverProbe Sync is not installed. Run ForeverProbe Setup.exe or Install.bat first.", "ForeverProbe Sync") | Out-Null
    return
  }
  $last = "never"
  if (Test-Path $LogFile) {
    $tail = Get-Content $LogFile -Tail 1
    if ($tail) { $last = $tail }
  }
  $files = @(Find-SavedVariables -Root ((Get-Content $CfgFile -Raw | ConvertFrom-Json).wowPath))
  $msg = "Watching " + $files.Count + " ForeverProbe file(s).`n`nLast activity:`n" + $last + "`n`nSync now?"
  $r = [System.Windows.Forms.MessageBox]::Show($msg, "ForeverProbe Sync", [System.Windows.Forms.MessageBoxButtons]::YesNo)
  if ($r -eq [System.Windows.Forms.DialogResult]::Yes) {
    $result = Run-Sync
    [System.Windows.Forms.MessageBox]::Show($result, "ForeverProbe Sync") | Out-Null
  }
}

if ($Uninstall) {
  schtasks /Delete /TN "$TaskName" /F 2>$null | Out-Null
  Stop-Tray
  foreach ($lnk in @((Join-Path ([Environment]::GetFolderPath("Programs")) "ForeverProbe Sync.lnk"),
                     (Join-Path ([Environment]::GetFolderPath("Desktop")) "ForeverProbe Sync.lnk"),
                     (Join-Path ([Environment]::GetFolderPath("Startup")) "ForeverProbe Sync.lnk"))) {
    if (Test-Path $lnk) { Remove-Item -Force $lnk }
  }
  if (Test-Path $AppDir) { Remove-Item -Recurse -Force $AppDir }
  Write-Host "ForeverProbe Sync removed completely."
  exit
}

function Show-Banner {
  $sigil = @'

           ..o000o..           ..o000o..
        o0'         '0o     o0'         '0o
       0               '0o0'              0
       0               .o0o.              0
        o0.         .0o     o0.         .0o
           ''o000o''           ''o000o''

        F O R E V E R P R O B E   S Y N C
'@
  Write-Host $sigil -ForegroundColor Yellow
  Write-Host "        foreverrank.com  ::  the guild sees what you see" -ForegroundColor DarkGray
  Write-Host ""
}

if ($Install) {
  New-Item -ItemType Directory -Force -Path $AppDir | Out-Null
  Show-Banner
  Write-Host "  Your play data ships to the guild automatically after each session."
  Write-Host ""
  # The guild key ships in the download; nobody types anything.
  $here = Split-Path $MyInvocation.MyCommand.Path
  $hook = ""; $mark = ""
  $keyFile = Join-Path $here "guild.key"
  $hookFile = Join-Path $here "webhook.txt"
  if (Test-Path $keyFile) {
    try {
      $raw = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String((Get-Content $keyFile -Raw).Trim()))
      $parts = $raw.Split("|")
      $hook = $parts[0]
      if ($parts.Count -gt 1) { $mark = $parts[1] }
      Write-Host "  Guild key found. No typing needed." -ForegroundColor Green
    } catch { }
  }
  if (-not $hook -and (Test-Path $hookFile)) {
    $hook = (Get-Content $hookFile -Raw).Trim()
    Write-Host "  Found webhook.txt. No typing needed." -ForegroundColor Green
  }
  if (-not $hook) { $hook = Read-Host "  Paste the guild's Discord webhook URL" }
  if (-not $hook.StartsWith("https://discord.com/api/webhooks/")) { Write-Host "  That does not look like a Discord webhook URL."; exit 1 }
  @{ webhook = $hook; mark = $mark; wowPath = $WowPath; sent = @{} } | ConvertTo-Json | Set-Content -Path $CfgFile
  $self = Join-Path $AppDir "ForeverProbe-Sync.ps1"
  Copy-Item -Force $MyInvocation.MyCommand.Path $self
  $srcIco = Join-Path (Split-Path $MyInvocation.MyCommand.Path) "ForeverProbe.ico"
  $ico = Join-Path $AppDir "ForeverProbe.ico"
  if (Test-Path $srcIco) { Copy-Item -Force $srcIco $ico }
  # The tray replaced the scheduled task; retire one an older build left behind.
  schtasks /Delete /TN "$TaskName" /F 2>$null | Out-Null
  Stop-Tray
  $trayArgs = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$self`" -Tray"
  # A clickable face: Start Menu and Desktop shortcuts that open the status box.
  # The shell's own folder answers are used, so OneDrive-redirected Desktops work.
  $ws = New-Object -ComObject WScript.Shell
  # The tray at every login: a shortcut in the Startup folder.
  try {
    $startupDir = [string]$ws.SpecialFolders.Item("Startup")
    if ($startupDir) {
      $lnk = $ws.CreateShortcut((Join-Path $startupDir "ForeverProbe Sync.lnk"))
      $lnk.TargetPath = "powershell.exe"
      $lnk.Arguments = $trayArgs
      $lnk.WorkingDirectory = $AppDir
      if (Test-Path $ico) { $lnk.IconLocation = "$ico,0" }
      $lnk.Description = "ForeverProbe Sync tray"
      $lnk.Save()
    }
  } catch {
    Write-Host ("  Could not add the Startup entry :: " + $_.Exception.Message) -ForegroundColor Red
  }
  $spots = @()
  try { $spots += [string]$ws.SpecialFolders.Item("Programs") } catch { }
  try { $spots += [string]$ws.SpecialFolders.Item("Desktop") } catch { }
  $od = Join-Path $env:USERPROFILE "OneDrive\Desktop"
  if ((Test-Path $od) -and ($spots -notcontains $od)) { $spots += $od }
  foreach ($dir in $spots) {
    if (-not $dir -or -not (Test-Path $dir)) { continue }
    $dest = Join-Path $dir "ForeverProbe Sync.lnk"
    try {
      $lnk = $ws.CreateShortcut($dest)
      $lnk.TargetPath = "powershell.exe"
      $lnk.Arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$self`" -Status"
      $lnk.WorkingDirectory = $AppDir
      if (Test-Path $ico) { $lnk.IconLocation = "$ico,0" }
      $lnk.Description = "ForeverProbe Sync: click for status and a manual sync"
      $lnk.Save()
      Write-Host ("  Icon created: " + $dest) -ForegroundColor Green
    } catch {
      Write-Host ("  Could not create icon at " + $dest + " :: " + $_.Exception.Message) -ForegroundColor Red
    }
  }
  Log "installed"
  Start-Process powershell -ArgumentList "-NoProfile","-WindowStyle","Hidden","-ExecutionPolicy","Bypass","-File",$self,"-Tray" -WindowStyle Hidden
  Write-Host ""
  Write-Host "  Installed." -ForegroundColor Green
  Write-Host "  The sigil is in your system tray by the clock. It syncs every 30"
  Write-Host "  minutes and shows a balloon when an update ships; right-click it"
  Write-Host "  for Sync now, Status and Exit. It comes back at every login, and"
  Write-Host "  the desktop icon opens the same status box."
  $found = @(Find-SavedVariables -Root $WowPath)
  if ($found.Count -eq 0) { Write-Host "  Note: no ForeverProbe data found yet; it appears after your first logout with the addon." }
  else { Write-Host ("  Watching: " + ($found -join ", ")) }
  Write-Host ""
  Read-Host "  Press Enter to close"
  exit
}

if ($Status) {
  Show-Status
  exit
}

if ($Tray) {
  Add-Type -AssemblyName System.Windows.Forms | Out-Null
  Add-Type -AssemblyName System.Drawing | Out-Null

  # One sigil in the tray is plenty; a second launch bows out quietly.
  $fresh = $false
  $mutex = New-Object System.Threading.Mutex($true, "ForeverProbeSyncTray", [ref]$fresh)
  if (-not $fresh) { exit }

  $icoFile = Join-Path $AppDir "ForeverProbe.ico"
  if (-not (Test-Path $icoFile)) { $icoFile = Join-Path (Split-Path $MyInvocation.MyCommand.Path) "ForeverProbe.ico" }
  $script:notify = New-Object System.Windows.Forms.NotifyIcon
  if (Test-Path $icoFile) { $script:notify.Icon = New-Object System.Drawing.Icon($icoFile) }
  else { $script:notify.Icon = [System.Drawing.SystemIcons]::Application }
  $script:notify.Text = "ForeverProbe Sync"

  # $loud balloons every outcome (manual sync); quiet passes balloon only sends.
  $script:doSync = {
    param([bool]$loud)
    $msg = Run-Sync
    if ($loud -or $msg -like "Sent *") {
      $script:notify.BalloonTipTitle = "ForeverProbe Sync"
      $script:notify.BalloonTipText  = $msg
      $script:notify.ShowBalloonTip(4000)
    }
  }

  $menu = New-Object System.Windows.Forms.ContextMenuStrip
  [void]$menu.Items.Add("Sync now", $null, { & $script:doSync $true })
  [void]$menu.Items.Add("Status", $null, { Show-Status })
  [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
  [void]$menu.Items.Add("Exit", $null, {
    $script:timer.Stop()
    $script:notify.Visible = $false
    $script:notify.Dispose()
    [System.Windows.Forms.Application]::Exit()
  })
  $script:notify.ContextMenuStrip = $menu
  $script:notify.Visible = $true

  # First pass shortly after the sigil appears, then every 30 minutes.
  $script:timer = New-Object System.Windows.Forms.Timer
  $script:timer.Interval = 15000
  $script:timer.Add_Tick({
    $script:timer.Interval = 1800000
    & $script:doSync $false
  })
  $script:timer.Start()
  Log "tray up"

  [System.Windows.Forms.Application]::Run((New-Object System.Windows.Forms.ApplicationContext))
  $mutex.ReleaseMutex()
  exit
}

# Default (and -SyncNow): one quiet sync pass, for shortcuts and old tasks.
Run-Sync | Out-Null
