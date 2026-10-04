QuestBank Uploader (Windows, optional)
======================================

Sends your QuestBank.lua to foreverrank.com after the game writes it
(at logout and on /reload), so what you discover in game reaches
everyone's QuestBank in the next data release. No account, no key,
nothing to type. Uploads are stored privately and never published as
they are (the file holds your characters' names); only what QuestBank
noted about quests, NPCs, items, spells and XP goes into the releases.

Setup, once: double-click Install.bat in this folder. It also puts the
QuestBank addon from this download into your game's Interface\AddOns.
A copy you already have is updated (the old one is kept as
Interface\QuestBank.bak); where there is none, it asks once.

Then the QuestBank Uploader icon sits in the system tray by the clock.
It sends every 30 minutes and starts again with Windows. Right-click it:

  Send now            send right away
  Status              your game folders with the QuestBank in each,
                      every QuestBank.lua it watches (size, when the
                      game wrote it, which QuestBank wrote it, sent or
                      not) and the last lines of its log
  Choose WoW folder   when WoW lives somewhere other than the usual
                      install folders
  Exit                stop it until the next login

The QuestBank Uploader icon on your desktop opens the same Status box.
Its log is %APPDATA%\QuestBank Uploader\uploader.log.

Remove it any time: double-click Uninstall.bat. The QuestBank addon and
your saved files stay.

Not on Windows? Upload QuestBank.lua by hand at
https://foreverrank.com/questbank/

Everything it does is readable in QuestBank-Uploader.ps1.
