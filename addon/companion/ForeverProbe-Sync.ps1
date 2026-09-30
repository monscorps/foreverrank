# ForeverProbe Sync: sends what your addons noted to foreverrank.com, automatically.
#
# What it does, in full: finds SavedVariables\ForeverProbe.lua and SavedVariables\QuestBank.lua
# under your WoW game folders and, when either file changes (WoW writes them at logout and on
# /reload), uploads it to foreverrank.com's data endpoint. Nothing else is read, nothing runs
# inside the game, no account or login is involved, and you can read every line below.
# The site keeps no player names: only what the addons noted about quests, NPCs and XP.
#
# Install:   Install.bat (or: .\ForeverProbe-Sync.ps1 -Install)
# Running:   the sigil sits in your system tray and syncs every 30 minutes;
#            right-click it for Sync now / Status / Exit. Returns at login.
# Remove:    double-click Uninstall.bat (or: -Uninstall)

param(
  [switch]$Install,
  [switch]$Uninstall,
  [switch]$Status,
  [switch]$SyncNow,
  [switch]$Tray,
  [string]$WowPath = "",
  [string]$Endpoint = ""
)

$DefaultEndpoint = "https://foreverrank.andustemme.workers.dev/api/probe"
$WatchFiles = @("ForeverProbe.lua", "QuestBank.lua")
$MaxBytes   = 6 * 1024 * 1024   # the endpoint's limit

$AppDir   = Join-Path $env:APPDATA "ForeverProbe"
$CfgFile  = Join-Path $AppDir "config.json"
$LogFile  = Join-Path $AppDir "sync.log"
$TaskName = "ForeverProbe Sync"   # older builds ran as a scheduled task

function Log([string]$msg) {
  $line = (Get-Date -Format "yyyy-MM-dd HH:mm:ss") + "  " + $msg
  Add-Content -Path $LogFile -Value $line -ErrorAction SilentlyContinue
}

function Read-Config {
  if (-not (Test-Path $CfgFile)) { return $null }
  $cfg = Get-Content $CfgFile -Raw | ConvertFrom-Json
  # older builds (0.3) posted to a guild webhook; that key is dropped, the endpoint is the site's
  $endpoint = $DefaultEndpoint
  if ($cfg.PSObject.Properties["endpoint"] -and $cfg.endpoint) { $endpoint = [string]$cfg.endpoint }
  $sent = @{}
  if ($cfg.PSObject.Properties["sent"] -and $cfg.sent) { $cfg.sent.PSObject.Properties | ForEach-Object { $sent[$_.Name] = $_.Value } }
  $wow = ""
  if ($cfg.PSObject.Properties["wowPath"] -and $cfg.wowPath) { $wow = [string]$cfg.wowPath }
  return @{ endpoint = $endpoint; wowPath = $wow; sent = $sent }
}

function Save-Config($cfg) {
  @{ endpoint = $cfg.endpoint; wowPath = $cfg.wowPath; sent = $cfg.sent } | ConvertTo-Json | Set-Content -Path $CfgFile
}

function Find-SavedVariables {
  param([string]$Root)
  $roots = @()
  if ($Root) { $roots += $Root }
  $roots += @("C:\Program Files (x86)\World of Warcraft", "C:\Program Files\World of Warcraft", "D:\World of Warcraft", "$env:USERPROFILE\World of Warcraft")
  foreach ($r in $roots) {
    if (-not (Test-Path -LiteralPath $r)) { continue }
    # every game folder (_classic_beta_ for the Forever beta, and whatever live Forever gets); the root
    # itself counts too, when it is a game folder
    $flavors = @(Get-ChildItem -Path $r -Directory -Filter "_*_" -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
    $flavors += $r
    foreach ($f in $flavors) {
      $acct = Join-Path $f "WTF\Account"
      if (Test-Path $acct) {
        # WoW names each file after the addon (ForeverProbe.lua, QuestBank.lua), not after the variable inside it
        Get-ChildItem -Path $acct -Recurse -File -Include $WatchFiles -ErrorAction SilentlyContinue |
          Where-Object { $_.Directory.Name -eq "SavedVariables" } | ForEach-Object { $_.FullName }
      }
    }
  }
}

# One multipart POST: source=companion, file=<the saved file>. The reply is JSON:
# { ok, id, kind, summary, message } or { ok, duplicate } or { error }.
function Send-ToForeverRank {
  param([string]$Url, [string]$File)
  $boundary = [System.Guid]::NewGuid().ToString()
  $LF = "`r`n"
  $bytes = [System.IO.File]::ReadAllBytes($File)
  $enc = [System.Text.Encoding]::GetEncoding("ISO-8859-1")
  $name = [System.IO.Path]::GetFileName($File)
  $pre = "--$boundary$LF" +
    "Content-Disposition: form-data; name=`"source`"$LF$LF" + "companion" + $LF +
    "--$boundary$LF" +
    "Content-Disposition: form-data; name=`"file`"; filename=`"$name`"$LF" +
    "Content-Type: text/plain$LF$LF"
  $post = "$LF--$boundary--$LF"
  # one byte array: PowerShell's + on two arrays makes an object[], which the web cmdlets would stringify
  [byte[]]$body = $enc.GetBytes($pre) + $bytes + $enc.GetBytes($post)
  try {
    return Invoke-RestMethod -Uri $Url -Method Post -ContentType "multipart/form-data; boundary=$boundary" -Body $body -TimeoutSec 60
  } catch {
    # the endpoint answers refusals with a JSON error line; surface it instead of the bare status
    $detail = ""
    if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $detail = $_.ErrorDetails.Message }
    elseif ($_.Exception.Response -and ($_.Exception.Response | Get-Member -Name GetResponseStream)) {
      try { $sr = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream()); $detail = $sr.ReadToEnd() } catch { }
    }
    $code = ""
    try { $code = [int]$_.Exception.Response.StatusCode } catch { }
    throw ("HTTP " + $code + " " + $detail).Trim()
  }
}

function Run-Sync {
  $cfg = Read-Config
  if (-not $cfg) { return "Not installed." }
  $files = @(Find-SavedVariables -Root $cfg.wowPath)
  if ($files.Count -eq 0) {
    Log "no SavedVariables\ForeverProbe.lua or QuestBank.lua found"
    return "No ForeverProbe or QuestBank data found yet. Log a character out once with either addon installed."
  }
  $posted = 0; $skipped = 0; $failed = 0
  foreach ($f in $files) {
    $hash = (Get-FileHash -Path $f -Algorithm SHA256).Hash
    if ($cfg.sent[$f] -eq $hash) { $skipped++; continue }
    $size = (Get-Item $f).Length
    if ($size -gt $MaxBytes) { $failed++; Log ("SKIPPED " + $f + " :: " + [math]::Round($size / 1MB, 1) + " MB is over the 6 MB limit"); continue }
    try {
      $r = Send-ToForeverRank -Url $cfg.endpoint -File $f
      if ($r -and $r.ok) {
        $cfg.sent[$f] = $hash
        $posted++
        if ($r.duplicate) { Log ("already there: " + $f) }
        else {
          $bits = @()
          if ($r.summary -and $r.summary.quests -ne $null) { $bits += ($r.summary.quests.ToString() + " quests noted") }
          if ($r.summary -and $r.summary.level -ne $null) { $bits += ("level " + $r.summary.level) }
          Log ("sent " + $f + " :: upload #" + $r.id + " (" + $r.kind + ") " + ($bits -join ", "))
        }
      } else {
        $failed++
        Log ("FAILED " + $f + " :: " + ($r | ConvertTo-Json -Compress))
      }
    } catch {
      $failed++
      Log ("FAILED " + $f + " :: " + $_.Exception.Message)
    }
  }
  Save-Config $cfg
  if ($failed -gt 0) { return "Sent $posted, failed $failed. See sync.log in $AppDir." }
  if ($posted -gt 0) { return "Sent $posted update(s) to foreverrank.com." }
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
  $cfg = Read-Config
  if (-not $cfg) {
    [System.Windows.Forms.MessageBox]::Show("ForeverProbe Sync is not installed. Run Install.bat first.", "ForeverProbe Sync") | Out-Null
    return
  }
  $last = "never"
  if (Test-Path $LogFile) {
    $tail = Get-Content $LogFile -Tail 1
    if ($tail) { $last = $tail }
  }
  $files = @(Find-SavedVariables -Root $cfg.wowPath)
  $msg = "Watching " + $files.Count + " saved file(s) for foreverrank.com.`n`nLast activity:`n" + $last + "`n`nSync now?"
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
  Write-Host "        foreverrank.com  ::  what you see, everyone learns" -ForegroundColor DarkGray
  Write-Host ""
}

if ($Install) {
  New-Item -ItemType Directory -Force -Path $AppDir | Out-Null
  Show-Banner
  Write-Host "  What ForeverProbe and QuestBank note in game ships to foreverrank.com"
  Write-Host "  automatically after each session. Nothing to type, no account."
  Write-Host ""
  $ep = $DefaultEndpoint
  if ($Endpoint) { $ep = $Endpoint }
  Save-Config @{ endpoint = $ep; wowPath = $WowPath; sent = @{} }
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
  if ($found.Count -eq 0) { Write-Host "  Note: no ForeverProbe or QuestBank data found yet; it appears after your first logout with either addon." }
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
$result = Run-Sync
if ($SyncNow) { Write-Host $result }
