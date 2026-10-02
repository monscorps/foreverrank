ForeverProbe Sync (Windows companion, optional)
================================================

Sends what ForeverProbe and QuestBank note in game to foreverrank.com
automatically, so you never have to export or upload by hand. The game
itself never sends anything; this small script runs outside WoW, watches
two saved files, and uploads each one when it changes:

  WTF\Account\<account>\SavedVariables\ForeverProbe.lua
  WTF\Account\<account>\SavedVariables\QuestBank.lua

Either addon on its own is enough; it uploads whichever files exist.
No account, no key, nothing to type. The site keeps no player names:
only what the addons noted about quests, NPCs and XP.

Setup, once:
  Double-click Install.bat in this folder.

After install the sigil sits in your system tray, by the clock. It
syncs every 30 minutes on its own, shows a balloon when an update
ships, and starts again with Windows. Right-click it:

  Sync now            push an update this second
  Status              the WoW folder; every saved file it watches (all
                      accounts under WTF\Account) with its size, when
                      the game last wrote it, which addon version wrote
                      it and whether it changed since the last send;
                      where the ForeverProbe addon sits in each game
                      folder; the last log lines
  Choose WoW folder   point it at your game folder when WoW lives
                      somewhere other than the usual install paths
  Exit                stop it until the next login

The ForeverProbe Sync icon on your desktop opens the same status box.

If Status says ForeverProbe.lua hasn't changed in days: the game only
writes that file while the ForeverProbe addon is loaded. In game, type
/qb probe (QuestBank 3.5.2 or newer) to see whether it is missing,
switched off for that character, or out of date. The addon also says
"ForeverProbe 0.4.3 is running" in chat the first time it loads.
The log of what was sent is %APPDATA%\ForeverProbe\sync.log.

Remove completely any time: double-click Uninstall.bat.

Everything the installer and tray do is readable in
ForeverProbe-Sync.ps1. The uploads land where the paste box on
https://foreverrank.com/questbank/ sends them, and go into the next
QuestBank data release.
