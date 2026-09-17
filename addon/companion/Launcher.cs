// ForeverProbe Setup: the double-click face of the companion installer.
// All it does is start the readable PowerShell installer next door:
//   Companion\ForeverProbe-Sync.ps1 -Install
// Compile on Windows with Build-Installer.bat (csc.exe ships with Windows).

using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;

static class Launcher
{
    [STAThread]
    static void Main()
    {
        string here = AppDomain.CurrentDomain.BaseDirectory;
        // At the zip root the script lives in Companion\; inside that folder
        // (someone moved the exe, or a dev build) it sits right next to us.
        string[] candidates = {
            Path.Combine(Path.Combine(here, "Companion"), "ForeverProbe-Sync.ps1"),
            Path.Combine(here, "ForeverProbe-Sync.ps1")
        };
        string script = null;
        foreach (string c in candidates)
            if (File.Exists(c)) { script = c; break; }

        // Double-clicked inside the un-extracted zip, Explorer unpacks only the
        // exe to a temp folder, so the script is missing: say what to do.
        if (script == null)
        {
            MessageBox.Show(
                "Could not find Companion\\ForeverProbe-Sync.ps1 next to this program.\n\n" +
                "Extract the whole ForeverProbe zip first (right-click the zip, Extract All), " +
                "then run ForeverProbe Setup from the extracted folder.",
                "ForeverProbe Setup", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }

        ProcessStartInfo psi = new ProcessStartInfo();
        psi.FileName = "powershell.exe";
        psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File \"" + script + "\" -Install";
        psi.UseShellExecute = true;
        psi.WorkingDirectory = Path.GetDirectoryName(script);
        try
        {
            Process.Start(psi);
        }
        catch (Exception ex)
        {
            MessageBox.Show("Could not start the installer:\n" + ex.Message,
                "ForeverProbe Setup", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }
}
