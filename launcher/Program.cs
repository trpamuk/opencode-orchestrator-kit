using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;

[assembly: System.Reflection.AssemblyTitle("OpenCode Orchestrator Kit")]
[assembly: System.Reflection.AssemblyProduct("OpenCode Orchestrator Kit")]
[assembly: System.Reflection.AssemblyDescription("Windows installer launcher for OpenCode Orchestrator Kit")]
[assembly: System.Reflection.AssemblyVersion("0.4.3.0")]
[assembly: System.Reflection.AssemblyFileVersion("0.4.3.0")]

static class Program
{
    [STAThread]
    static void Main()
    {
        string baseDir = AppDomain.CurrentDomain.BaseDirectory;
        string script = Path.Combine(baseDir, "install-gui.ps1");
        if (!File.Exists(script))
        {
            MessageBox.Show(
                "install-gui.ps1 bulunamadi. ZIP'i eksiksiz cikardiginizdan emin olun.",
                "OpenCode Orchestrator Kit",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
            return;
        }

        try
        {
            ProcessStartInfo psi = new ProcessStartInfo();
            psi.FileName = "powershell.exe";
            psi.Arguments = "-STA -NoProfile -ExecutionPolicy Bypass -File \"" + script + "\"";
            psi.WorkingDirectory = baseDir;
            psi.UseShellExecute = true;
            Process.Start(psi);
        }
        catch (Exception ex)
        {
            MessageBox.Show(
                "Installer baslatilamadi:\r\n" + ex.Message,
                "OpenCode Orchestrator Kit",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
        }
    }
}
