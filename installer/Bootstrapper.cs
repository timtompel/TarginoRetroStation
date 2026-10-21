using System;
using System.IO;
using System.Reflection;
using System.Diagnostics;
using System.Drawing;
using System.Windows.Forms;
using System.Web.Script.Serialization;

[assembly: AssemblyTitle("Targino RetroStation - Instalador Web")]
[assembly: AssemblyProduct("TarginoRetroStation")]
[assembly: AssemblyVersion("1.5.2.0")]
[assembly: AssemblyInformationalVersion("1.5.2")]
public sealed class Bootstrapper : Form
{
    Label status; ProgressBar progress; Button start,cancel; Timer timer;
    Process worker; string job,package,packageHash; long packageSize; bool closing;
    static readonly JavaScriptSerializer Json=new JavaScriptSerializer();
    static readonly string Ps=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),@"WindowsPowerShell\v1.0\powershell.exe");
    [STAThread] public static int Main() {
        Application.EnableVisualStyles();Application.SetCompatibleTextRenderingDefault(false);
        Application.Run(new Bootstrapper());return 0;
    }
    public Bootstrapper() {
        Text="Targino RetroStation — Instalador Web";ClientSize=new Size(620,290);StartPosition=FormStartPosition.CenterScreen;
        FormBorderStyle=FormBorderStyle.FixedDialog;MaximizeBox=false;Font=new Font("Segoe UI",10);
        Icon=Icon.ExtractAssociatedIcon(Assembly.GetExecutingAssembly().Location);
        Controls.Add(new Label{Text="Targino RetroStation",Left=24,Top=20,Width=570,Height=42,Font=new Font("Segoe UI",22,FontStyle.Bold)});
        Controls.Add(new Label{Text="Baixa somente a versao estavel oficial e verifica sua assinatura.\r\nNao inclui Hydra, jogos ou BIOS. O Setup permite escolher a pasta.",Left=26,Top=76,Width=570,Height=55});
        status=new Label{Text="Conexao com a internet necessaria.",Left=26,Top=143,Width=570,Height=45};Controls.Add(status);
        progress=new ProgressBar{Left=26,Top=195,Width=570,Height=16};Controls.Add(progress);
        start=new Button{Text="Baixar instalador",Left=285,Top=232,Width=165,Height=36};Controls.Add(start);start.Click+=delegate{StartOrInstall();};
        cancel=new Button{Text="Fechar",Left=460,Top=232,Width=136,Height=36};Controls.Add(cancel);cancel.Click+=delegate{Close();};
        timer=new Timer{Interval=400};timer.Tick+=delegate{Observe();};
        FormClosing+=delegate(object sender,FormClosingEventArgs e){
            if(worker!=null&&!worker.HasExited){File.WriteAllText(Path.Combine(job,"cancel"),"cancel");status.Text="Cancelando com seguranca...";closing=true;e.Cancel=true;}
        };
        FormClosed+=delegate{timer.Stop();timer.Dispose();if(worker!=null)worker.Dispose();};
    }
    void StartOrInstall() {
        if(package!=null) {
            try {
                if(new FileInfo(package).Length!=packageSize)throw new IOException("Pacote foi alterado. Baixe novamente.");
                using(var sha=System.Security.Cryptography.SHA256.Create())using(var input=File.OpenRead(package)){
                    if(!BitConverter.ToString(sha.ComputeHash(input)).Replace("-","").Equals(packageHash,StringComparison.OrdinalIgnoreCase))throw new IOException("Hash do pacote mudou. Baixe novamente.");
                }
                var installer=Process.Start(new ProcessStartInfo(package){UseShellExecute=true,WorkingDirectory=job});File.WriteAllText(Path.Combine(job,"ready-to-install"),Json.Serialize(new{InstallerPid=installer.Id}));Close();}
            catch(Exception ex){package=null;status.Text=ex.Message;start.Text="Tentar novamente";}
            return;
        }
        try {
            if(!Environment.Is64BitOperatingSystem||!File.Exists(Ps))throw new Exception("Requer Windows x64 e Windows PowerShell 5.1.");
            job=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),@"TarginoRetroStation\WebInstaller\"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(job);
            foreach(string name in new[]{"BootstrapWorker.ps1","FrontendUpdate.ps1","Hashing.ps1","UpdateCache.ps1","UpdatePublicKey.xml"}) {
                using(var source=Assembly.GetExecutingAssembly().GetManifestResourceStream(name))using(var output=File.Create(Path.Combine(job,name)))source.CopyTo(output);
            }
            worker=Process.Start(new ProcessStartInfo(Ps,"-NoProfile -STA -ExecutionPolicy Bypass -File \""+Path.Combine(job,"BootstrapWorker.ps1")+"\" -Job \""+job+"\""){UseShellExecute=false,CreateNoWindow=true,WorkingDirectory=job});
            File.WriteAllText(Path.Combine(job,"active.json"),Json.Serialize(new{WorkerPid=worker.Id}));
            start.Enabled=false;cancel.Text="Cancelar";status.Text="Conectando...";timer.Start();
        }catch(Exception ex){status.Text=ex.Message;start.Enabled=true;start.Text="Tentar novamente";}
    }
    void Observe() {
        try {
            string path=Path.Combine(job,"status.json");
            if(File.Exists(path)) {
                var state=Json.DeserializeObject(File.ReadAllText(path)) as System.Collections.Generic.Dictionary<string,object>;
                status.Text=(string)state["Message"];progress.Value=Math.Max(0,Math.Min(100,Convert.ToInt32(state["Percent"])));
                string phase=(string)state["Phase"];
                if(phase=="ready"&&worker.HasExited) {
                    string candidate=Path.GetFullPath((string)state["Package"]);
                    if(!candidate.StartsWith(job+Path.DirectorySeparatorChar,StringComparison.OrdinalIgnoreCase)||Path.GetExtension(candidate)!=".exe")throw new Exception("Destino de pacote invalido.");
                    package=candidate;packageHash=(string)state["Sha256"];packageSize=Convert.ToInt64(state["Size"]);start.Text="Instalar";start.Enabled=true;cancel.Text="Fechar";timer.Stop();
                }else if(phase=="error"&&worker.HasExited){timer.Stop();start.Enabled=true;start.Text="Tentar novamente";cancel.Text="Fechar";}
            }
            if(worker.HasExited) {
                if(closing){Close();return;}
                if(!start.Enabled){timer.Stop();start.Enabled=true;start.Text="Tentar novamente";cancel.Text="Fechar";status.Text="Download interrompido. Tente novamente.";}
            }
        }catch(IOException){}catch(ArgumentException){}catch(System.Collections.Generic.KeyNotFoundException){}catch(Exception ex){timer.Stop();status.Text=ex.Message;}
    }
}
