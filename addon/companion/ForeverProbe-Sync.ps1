# ForeverProbe Sync: ships your ForeverProbe data to the guild automatically.
#
# What it does, in full: finds ForeverProbeDB.lua under your WoW beta's
# SavedVariables, and when the file changes (WoW writes it at logout and on
# /reload), posts it to the guild's private Discord webhook. Nothing else is
# read, nothing runs inside the game, and you can read every line below.
#
# One-time setup (PowerShell):
#   .\ForeverProbe-Sync.ps1 -Install
# It asks for the webhook URL (get it from the guild Discord), then registers
# a background task that checks every 30 minutes.
# Remove completely with: .\ForeverProbe-Sync.ps1 -Uninstall

param(
  [switch]$Install,
  [switch]$Uninstall,
  [string]$WowPath = ""
)

$AppDir  = Join-Path $env:APPDATA "ForeverProbe"
$CfgFile = Join-Path $AppDir "config.json"
$TaskName = "ForeverProbe Sync"

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
  param([string]$Webhook, [string]$File)
  $boundary = [System.Guid]::NewGuid().ToString()
  $LF = "`r`n"
  $bytes = [System.IO.File]::ReadAllBytes($File)
  $enc = [System.Text.Encoding]::GetEncoding("ISO-8859-1")
  $who = $env:USERNAME
  $pre = "--$boundary$LF" +
    "Content-Disposition: form-data; name=`"payload_json`"$LF$LF" +
    ('{"content":"ForeverProbe drop from **' + $who + '**, ' + (Get-Date -Format "yyyy-MM-dd HH:mm") + '"}') + $LF +
    "--$boundary$LF" +
    "Content-Disposition: form-data; name=`"file`"; filename=`"ForeverProbeDB.lua`"$LF" +
    "Content-Type: application/octet-stream$LF$LF"
  $post = "$LF--$boundary--$LF"
  $body = $enc.GetBytes($pre) + $bytes + $enc.GetBytes($post)
  Invoke-RestMethod -Uri $Webhook -Method Post -ContentType "multipart/form-data; boundary=$boundary" -Body $body | Out-Null
}

if ($Uninstall) {
  schtasks /Delete /TN "$TaskName" /F 2>$null
  if (Test-Path $AppDir) { Remove-Item -Recurse -Force $AppDir }
  Write-Host "ForeverProbe Sync removed."
  exit
}

if ($Install) {
  New-Item -ItemType Directory -Force -Path $AppDir | Out-Null
  $hook = Read-Host "Paste the guild's Discord webhook URL"
  if (-not $hook.StartsWith("https://discord.com/api/webhooks/")) { Write-Host "That does not look like a Discord webhook URL."; exit 1 }
  @{ webhook = $hook; wowPath = $WowPath; sent = @{} } | ConvertTo-Json | Set-Content -Path $CfgFile
  $self = Join-Path $AppDir "ForeverProbe-Sync.ps1"
  Copy-Item -Force $MyInvocation.MyCommand.Path $self
  $action = "powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$self`""
  schtasks /Create /TN "$TaskName" /TR $action /SC MINUTE /MO 30 /F | Out-Null
  Write-Host "Installed. Your ForeverProbe data now ships to the guild automatically after each session."
  $found = @(Find-SavedVariables -Root $WowPath)
  if ($found.Count -eq 0) { Write-Host "Note: no ForeverProbeDB.lua found yet. It appears after your first logout with the addon." }
  else { Write-Host ("Watching: " + ($found -join ", ")) }
  exit
}

# ---- sync run (what the scheduled task executes) --------------------------
if (-not (Test-Path $CfgFile)) { exit }
$cfg = Get-Content $CfgFile -Raw | ConvertFrom-Json
$sentHashes = @{}
if ($cfg.sent) { $cfg.sent.PSObject.Properties | ForEach-Object { $sentHashes[$_.Name] = $_.Value } }
$changed = $false
foreach ($f in @(Find-SavedVariables -Root $cfg.wowPath)) {
  $hash = (Get-FileHash -Path $f -Algorithm SHA256).Hash
  if ($sentHashes[$f] -ne $hash) {
    try {
      Send-ToWebhook -Webhook $cfg.webhook -File $f
      $sentHashes[$f] = $hash
      $changed = $true
    } catch { }
  }
}
if ($changed) {
  $cfg.sent = $sentHashes
  $cfg | ConvertTo-Json | Set-Content -Path $CfgFile
}
