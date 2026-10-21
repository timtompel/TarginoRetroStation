using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Web.Script.Serialization;
using System.Windows.Forms;

[assembly: AssemblyTitle("Instalador TarginoRetroStation")]
[assembly: AssemblyDescription("Complemento visual para uma instalacao existente do Hydra")]
[assembly: AssemblyVersion("1.5.3.0")]
[assembly: AssemblyFileVersion("1.5.3.0")]
[assembly: AssemblyProduct("TarginoRetroStation")]
[assembly: AssemblyInformationalVersion("1.5.3")]
public class PackageFile { public string Path {get;set;} public string Sha256 {get;set;} }
public class PackageManifest { public string Version {get;set;} public PackageFile[] Files {get;set;} }
public class Installer : Form
{
    TextBox destination;
    CheckBox shortcut, migrate;
    Button browse, install, open;
    Label status;
    ProgressBar progress;
    BackgroundWorker worker;
    string installedRoot;
    static readonly JavaScriptSerializer Json = new JavaScriptSerializer();
    const string HydraSite="https://hydrafrontend.com/";
    const string HydraDownload="https://hydrafrontend.com/hydra.exe";
    static readonly string Ps = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), @"WindowsPowerShell\v1.0\powershell.exe");
    [STAThread] public static int Main(string[] args)
    {
        if(args.Length == 3 && args[0] == "--apply-update") {
            try {
                int pid;
                if(!Int32.TryParse(args[2],out pid)||pid<=0)throw new Exception("Processo invalido.");
                try { using(var p=Process.GetProcessById(pid)) { if(!p.WaitForExit(60000))throw new Exception("O launcher ainda esta aberto. Atualizacao cancelada."); } }
                catch(ArgumentException) {}
                Install(args[1],true,true,null);
                StartFrontend(args[1]);return 0;
            } catch(Exception ex) {MessageBox.Show(ex.Message,"Atualizacao nao concluida",MessageBoxButtons.OK,MessageBoxIcon.Error);return 1;}
        }
        if(args.Length == 2 && (args[0] == "--extract-only" || args[0] == "--test-migrate")) {
            try { Install(args[1], false, args[0] == "--test-migrate", null); Console.WriteLine("INSTALL_OK"); return 0; }
            catch(Exception ex) { Console.Error.WriteLine(ex.ToString()); return 1; }
        }
        Application.EnableVisualStyles(); Application.SetCompatibleTextRenderingDefault(false);
        Application.Run(new Installer()); return 0;
    }
    Installer()
    {
        Text="Instalar Targino RetroStation 1.5.3";
        Size=new Size(740,490); MinimumSize=Size; MaximumSize=Size;
        Icon=Icon.ExtractAssociatedIcon(Assembly.GetExecutingAssembly().Location);
        StartPosition=FormStartPosition.CenterScreen; FormBorderStyle=FormBorderStyle.FixedDialog; MaximizeBox=false;
        BackColor=Color.FromArgb(13,18,28); ForeColor=Color.White; Font=new Font("Segoe UI",10);
        AddLabel("Targino RetroStation",26,22,660,44,23,Color.FromArgb(77,179,255));
        AddLabel("Instale o complemento na pasta onde o seu Hydra ja esta instalado.",28,80,660,28,11,Color.White);
        AddLabel("O pacote contem apenas o launcher, seu layout e os auxiliares de imagens.\r\nHydra, cores, ROMs e BIOS ficam sob responsabilidade do usuario.",28,116,660,52,10,Color.Silver);
        AddWebLink(this,"Site oficial do Hydra",HydraSite,28,166,230);
        AddWebLink(this,"Baixar hydra.exe",HydraDownload,280,166,300);
        AddLabel("Pasta do Hydra (deve conter hydra.exe)",28,187,630,24,10,Color.White);
        destination=new TextBox{Left=28,Top=215,Width=530,Text=Directory.Exists(@"D:\Games\hydra")?@"D:\Games\hydra":""};Controls.Add(destination);
        browse=new Button{Left=570,Top=213,Width=112,Height=31,Text="Procurar..."};Controls.Add(browse);
        browse.Click+=delegate{using(var dialog=new FolderBrowserDialog()){dialog.Description="Escolha a pasta do Hydra ja instalado";dialog.SelectedPath=destination.Text;if(dialog.ShowDialog(this)==DialogResult.OK)destination.Text=dialog.SelectedPath;}};
        shortcut=new CheckBox{Left=28,Top=264,Width=650,Height=25,Text="Criar atalho Targino RetroStation na area de trabalho",Checked=true};Controls.Add(shortcut);
        migrate=new CheckBox{Left=28,Top=294,Width=650,Height=25,Text="Reaproveitar e consolidar a instalacao antiga, sem duplicar as artes",Checked=true};Controls.Add(migrate);
        progress=new ProgressBar{Left=28,Top=334,Width=654,Height=18};Controls.Add(progress);
        status=AddLabel("A instalacao atual do Hydra e os seus jogos serao preservados.",28,360,654,32,9,Color.Silver);
        install=new Button{Left=502,Top=401,Width=180,Height=35,Text="Instalar complemento",BackColor=Color.FromArgb(35,133,207),ForeColor=Color.White,FlatStyle=FlatStyle.Flat};Controls.Add(install);
        open=new Button{Left=312,Top=401,Width=180,Height=35,Text="Abrir launcher",Visible=false};Controls.Add(open);
        open.Click+=delegate{StartFrontend(installedRoot);Close();};
        install.Click+=delegate{BeginInstall();};
        FormClosing+=delegate(object sender,FormClosingEventArgs e){if(worker!=null&&worker.IsBusy)e.Cancel=true;};
    }
    Label AddLabel(string text,int x,int y,int w,int h,float size,Color color)
    {
        var label=new Label{Text=text,Left=x,Top=y,Width=w,Height=h,ForeColor=color,Font=new Font("Segoe UI",size, size>20?FontStyle.Bold:FontStyle.Regular)};Controls.Add(label);return label;
    }
    void BeginInstall()
    {
        string root=destination.Text.Trim();bool createShortcut=shortcut.Checked;bool usePrevious=migrate.Checked;
        try {ValidateRoot(root);}
        catch(FileNotFoundException){using(var help=CreateHydraHelp(root)){help.ShowDialog(this);}return;}
        catch(Exception ex){MessageBox.Show(this,ex.Message,"Pasta do Hydra",MessageBoxButtons.OK,MessageBoxIcon.Information);return;}
        destination.Enabled=browse.Enabled=shortcut.Enabled=migrate.Enabled=install.Enabled=false;
        worker=new BackgroundWorker{WorkerReportsProgress=true};
        worker.DoWork+=delegate {Install(root,createShortcut,usePrevious,delegate(int percent,string text){worker.ReportProgress(percent,text);});};
        worker.ProgressChanged+=delegate(object sender,ProgressChangedEventArgs e){progress.Value=Math.Max(0,Math.Min(100,e.ProgressPercentage));status.Text=(string)e.UserState;};
        worker.RunWorkerCompleted+=delegate(object sender,RunWorkerCompletedEventArgs e){
            if(e.Error!=null){status.Text="A instalacao nao foi concluida.";MessageBox.Show(this,e.Error.Message,"Instalacao",MessageBoxButtons.OK,MessageBoxIcon.Error);destination.Enabled=browse.Enabled=shortcut.Enabled=migrate.Enabled=install.Enabled=true;return;}
            installedRoot=Path.GetFullPath(root);progress.Value=100;status.Text="Instalado em "+Path.Combine(installedRoot,"TarginoRetroStation");install.Hide();
            open.Visible=true;var finish=new Button{Left=502,Top=401,Width=180,Height=35,Text="Concluir"};finish.Click+=delegate{Close();};Controls.Add(finish);
        };
        worker.RunWorkerAsync();
    }
    static void ValidateRoot(string root)
    {
        if(string.IsNullOrWhiteSpace(root))throw new Exception("Escolha a pasta do Hydra.");
        string full=Path.GetFullPath(root);
        if(!Directory.Exists(full))throw new Exception("A pasta selecionada nao existe.");
        string hydra=Path.Combine(full,"hydra.exe");
        if(!File.Exists(hydra))throw new FileNotFoundException("hydra.exe nao encontrado na pasta raiz selecionada. Baixe e instale o Hydra primeiro. Site: "+HydraSite+" Download: "+HydraDownload,hydra);
        using(var stream=File.OpenRead(hydra)){if(stream.ReadByte()!=77||stream.ReadByte()!=90)throw new Exception("O hydra.exe selecionado nao possui cabecalho de executavel Windows.");}
        if(!File.Exists(Ps))throw new Exception("Windows PowerShell nao encontrado. Ative o Windows PowerShell 5.1 no Windows antes de instalar.");
        if(!Environment.Is64BitOperatingSystem)throw new Exception("Este complemento requer Windows de 64 bits.");
    }
    static LinkLabel AddWebLink(Control parent,string text,string url,int x,int y,int width)
    {
        var link=new LinkLabel{Text=text,AccessibleName=text+": "+url,Left=x,Top=y,Width=width,Height=22,LinkColor=Color.FromArgb(100,195,255),ActiveLinkColor=Color.White};
        link.LinkClicked+=delegate{
            try{Process.Start(new ProcessStartInfo(url){UseShellExecute=true});}
            catch(Exception error){MessageBox.Show(parent,"Nao foi possivel abrir o navegador. Acesse: "+url+"\r\n"+error.Message,"Site oficial do Hydra",MessageBoxButtons.OK,MessageBoxIcon.Information);}
        };
        parent.Controls.Add(link);return link;
    }
    static Form CreateHydraHelp(string root)
    {
        var dialog=new Form{Text="Hydra nao encontrado",ClientSize=new Size(650,340),StartPosition=FormStartPosition.CenterParent,FormBorderStyle=FormBorderStyle.FixedDialog,MaximizeBox=false,MinimizeBox=false,Font=new Font("Segoe UI",10),BackColor=Color.FromArgb(13,18,28),ForeColor=Color.White};
        dialog.Controls.Add(new Label{Text="O TarginoRetroStation e um complemento: o Hydra nao vem no pacote.\r\nNao encontramos hydra.exe na pasta raiz selecionada:",Left=22,Top=18,Width=605,Height=52});
        dialog.Controls.Add(new TextBox{Text=root,ReadOnly=true,Left=22,Top=78,Width=605});
        AddWebLink(dialog,HydraSite,HydraSite,22,122,605);
        AddWebLink(dialog,HydraDownload,HydraDownload,22,154,605);
        dialog.Controls.Add(new Label{Text="Baixe e execute o Hydra nessa pasta para concluir a instalacao inicial.\r\nDepois volte ao instalador e clique em Instalar complemento.\r\nROMs e BIOS continuam por conta do usuario. Nada sera baixado\r\nou executado automaticamente por este instalador.",Left=22,Top=195,Width=605,Height=85});
        var close=new Button{Text="Voltar ao instalador",Left=430,Top=293,Width=197,Height=32,DialogResult=DialogResult.Cancel};
        dialog.Controls.Add(close);dialog.CancelButton=close;return dialog;
    }
    static string Hash(string path)
    {
        using(var sha=SHA256.Create())using(var stream=File.OpenRead(path))return BitConverter.ToString(sha.ComputeHash(stream)).Replace("-","").ToLowerInvariant();
    }
    static string ReadResource(string name)
    {
        using(var stream=Assembly.GetExecutingAssembly().GetManifestResourceStream(name))using(var reader=new StreamReader(stream,Encoding.UTF8))return reader.ReadToEnd();
    }
    static void Report(Action<int,string> report,int percent,string message){if(report!=null)report(percent,message);}
    static void Install(string root,bool createShortcut,bool migrate,Action<int,string> report)
    {
        ValidateRoot(root);root=Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar);
        var manifest=Json.Deserialize<PackageManifest>(ReadResource("hydra.manifest.json"));
        string addon=Path.Combine(root,"TarginoRetroStation");
        if(Directory.Exists(addon) && (File.GetAttributes(addon)&FileAttributes.ReparsePoint)!=0)throw new Exception("A pasta TarginoRetroStation e um link. Escolha uma instalacao com pasta local.");
        string backup=Path.Combine(addon,@"Backups\Instalador\"+DateTime.Now.ToString("yyyyMMdd-HHmmss-fff"));
        var migration=new LegacyMigration(root,migrate);
        migration.Begin();
        var written=new List<string>();var backed=new Dictionary<string,string>(StringComparer.OrdinalIgnoreCase);
        var preservedBrand=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var expected=new Dictionary<string,string>(StringComparer.OrdinalIgnoreCase);
        foreach(var file in manifest.Files)expected.Add(file.Path.Replace('\\','/'),file.Sha256);
        try {
            using(var stream=Assembly.GetExecutingAssembly().GetManifestResourceStream("hydra.payload.zip"))
            using(var zip=new ZipArchive(stream,ZipArchiveMode.Read)) {
                int count=0;
                foreach(var entry in zip.Entries){
                    string entryName=entry.FullName.Replace('\\','/');
                    string destination=Path.GetFullPath(Path.Combine(root,entryName.Replace('/',Path.DirectorySeparatorChar)));
                    if(!destination.StartsWith(root+Path.DirectorySeparatorChar,StringComparison.OrdinalIgnoreCase))throw new Exception("Caminho invalido no pacote.");
                    if(!(entryName.StartsWith("TarginoRetroStation/",StringComparison.Ordinal)||entryName=="Abrir-TarginoRetroStation.cmd"))throw new Exception("O pacote tentou gravar fora do complemento.");
                    AtomicInstall.AssertLocalParents(root,destination);
                    string parent=Path.GetDirectoryName(destination);Directory.CreateDirectory(parent);
                    if(entryName.StartsWith("TarginoRetroStation/Marca/",StringComparison.Ordinal) && File.Exists(destination)){preservedBrand.Add(destination);continue;}
                    string expectedHash;
                    if(!expected.TryGetValue(entryName,out expectedHash))throw new Exception("Arquivo fora do manifesto: "+entryName);
                    if(File.Exists(destination)&&Hash(destination).Equals(expectedHash,StringComparison.OrdinalIgnoreCase))continue;
                    if(File.Exists(destination)){string copy=Path.Combine(backup,entryName.Replace('/',Path.DirectorySeparatorChar));AtomicInstall.AssertLocalParents(root,copy);Directory.CreateDirectory(Path.GetDirectoryName(copy));File.Copy(destination,copy,false);backed[destination]=copy;}
                    written.Add(destination);
                    using(var input=entry.Open())AtomicInstall.Write(input,destination,expectedHash);
                    count++;Report(report,5+count*55/Math.Max(1,zip.Entries.Count),"Instalando "+Path.GetFileName(destination));
                }
            }
            foreach(var file in manifest.Files){string path=Path.Combine(root,file.Path.Replace('/',Path.DirectorySeparatorChar));if(!preservedBrand.Contains(path)&&!Hash(path).Equals(file.Sha256,StringComparison.OrdinalIgnoreCase))throw new Exception("Arquivo nao passou na verificacao: "+file.Path);}
            migration.MergeAndReanchor();
            string obsolete=Path.Combine(addon,"hydra-media-transport.py");
            if(File.Exists(obsolete)&&Hash(obsolete)=="349cf501deddb0ba54c3638f562d43423cf01865162ffa891383d5f76de3b5d1"){
                string retired=Path.Combine(backup,@"Obsoletos\hydra-media-transport.py");
                AtomicInstall.AssertLocalParents(root,obsolete);AtomicInstall.AssertLocalParents(root,retired);
                Directory.CreateDirectory(Path.GetDirectoryName(retired));backed[obsolete]=retired;written.Add(obsolete);
                File.Move(obsolete,retired);
            }
            string data=Path.Combine(addon,"Dados");Directory.CreateDirectory(data);
            string layout=Path.Combine(data,"layout.json");
            if(!File.Exists(layout)){
                string template=File.ReadAllText(Path.Combine(data,"layout.template.json"),Encoding.UTF8);
                var settings=Json.Deserialize<Dictionary<string,object>>(template);
                foreach(string name in new[]{"BackgroundImage","AvatarImage"})if(settings.ContainsKey(name)&&settings[name]!=null)settings[name]=settings[name].ToString().Replace("{InstallDir}",root);
                File.WriteAllText(layout,Json.Serialize(settings),new UTF8Encoding(true));
            }
            Report(report,75,"Verificando dependencias do launcher...");
            var psi=new ProcessStartInfo(Ps,"-NoProfile -STA -ExecutionPolicy Bypass -File \""+Path.Combine(addon,"Verificar-Dependencias-Launcher.ps1")+"\" -FrontendDir \""+addon+"\""){UseShellExecute=false,CreateNoWindow=true,RedirectStandardOutput=true,WorkingDirectory=root};
            using(var process=Process.Start(psi)){string output=process.StandardOutput.ReadToEnd();process.WaitForExit();if(process.ExitCode!=0)throw new Exception("Dependencias: "+output);}
            File.WriteAllText(Path.Combine(data,"instalacao.json"),Json.Serialize(new{Version=manifest.Version,Installed=DateTime.Now.ToString("s"),Location=addon}),new UTF8Encoding(true));
            migration.Commit();
            if(createShortcut){Report(report,90,"Criando atalho...");CreateShortcut(root);}
            Report(report,100,"Complemento instalado. "+migration.Summary);
        } catch {
            if(migration.CleanupCommitted)throw;
            try{migration.RollbackChanges();}catch{}
            foreach(string file in written){try{if(backed.ContainsKey(file))File.Copy(backed[file],file,true);else File.Delete(file);}catch{}}
            try{migration.UndoRename();}catch{}
            throw;
        }
    }
    static void CreateShortcut(string root)
    {
        Type type=Type.GetTypeFromProgID("WScript.Shell");if(type==null)return;
        dynamic shell=Activator.CreateInstance(type);
        dynamic link=shell.CreateShortcut(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory),"Targino RetroStation.lnk"));
        link.TargetPath=Ps;link.Arguments="-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File \""+Path.Combine(root,@"TarginoRetroStation\Launcher.ps1")+"\"";
        link.WorkingDirectory=root;link.Description="Targino RetroStation - complemento visual";link.IconLocation=Path.Combine(root,@"TarginoRetroStation\Launcher.ico")+",0";link.Save();
        string oldLink=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory),"TarginoLauncher.lnk");
        if(File.Exists(oldLink)&&!Directory.Exists(Path.Combine(root,"TarginoLauncher"))){
            dynamic previous=shell.CreateShortcut(oldLink);
            string args=(string)previous.Arguments,oldScript=Path.Combine(root,@"TarginoLauncher\Launcher.ps1");
            if(args.IndexOf(oldScript,StringComparison.OrdinalIgnoreCase)>=0){
                string backup=Path.Combine(root,@"TarginoRetroStation\Backups\Atalhos\"+DateTime.Now.ToString("yyyyMMdd-HHmmss-fff"));
                Directory.CreateDirectory(backup);string copy=Path.Combine(backup,"TarginoLauncher.lnk");File.Copy(oldLink,copy,false);
                if(Hash(copy)==Hash(oldLink))File.Delete(oldLink);
            }
        }
    }
    static void StartFrontend(string root)
    {
        Process.Start(new ProcessStartInfo(Ps,"-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File \""+Path.Combine(root,@"TarginoRetroStation\Launcher.ps1")+"\""){WorkingDirectory=root,UseShellExecute=true,WindowStyle=ProcessWindowStyle.Hidden});
    }
}
