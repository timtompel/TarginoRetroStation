using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Security.Cryptography;
using System.Text;
using System.Web.Script.Serialization;

// One-time migration of the Hydra add-on only. Never traverses ROMs/BIOS/Saves.
public sealed class LegacyMigration
{
    readonly string oldDir,newDir,backup;
    readonly JavaScriptSerializer json=new JavaScriptSerializer {MaxJsonLength=Int32.MaxValue};
    readonly List<string[]> moved=new List<string[]>();
    readonly Dictionary<string,string> rewritten=new Dictionary<string,string>();
    readonly List<string[]> remaining=new List<string[]>();
    bool renamed,enabled;
    public bool ReusedDirectory {get{return renamed;}}
    public bool CleanupCommitted {get;private set;}
    public string Summary {get;private set;}
    public LegacyMigration(string root,bool requested)
    {
        root=Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar);
        oldDir=Path.Combine(root,"TarginoLauncher");newDir=Path.Combine(root,"TarginoRetroStation");
        backup=Path.Combine(newDir,@"Backups\Migracao-1.4.2\"+DateTime.Now.ToString("yyyyMMdd-HHmmss-fff"));
        if(!requested||!Directory.Exists(oldDir))return;
        if(!File.Exists(Path.Combine(oldDir,"HydraLibrary.ps1"))||!File.Exists(Path.Combine(oldDir,"Launcher.ps1")))throw new Exception("A pasta TarginoLauncher nao foi identificada como complemento Hydra. Nada foi removido.");
        SafeTree(oldDir);if(Directory.Exists(newDir))SafeTree(newDir);
        enabled=true;
    }
    static void SafeTree(string path)
    {
        if((File.GetAttributes(path)&FileAttributes.ReparsePoint)!=0)throw new Exception("Migracao recusada: link/juncao em "+path);
        foreach(string child in Directory.GetFileSystemEntries(path)){
            var attr=File.GetAttributes(child);
            if((attr&FileAttributes.ReparsePoint)!=0)throw new Exception("Migracao recusada: link/juncao em "+child);
            if((attr&FileAttributes.Directory)!=0)SafeTree(child);
        }
    }
    static string Hash(string path){using(var a=SHA256.Create())using(var s=File.OpenRead(path))return BitConverter.ToString(a.ComputeHash(s)).Replace("-","");}
    static string Hash(Stream stream){using(var a=SHA256.Create())return BitConverter.ToString(a.ComputeHash(stream)).Replace("-","");}
    public void Begin()
    {
        if(enabled&&!Directory.Exists(newDir)){
            // These exact, validated siblings are the only rename targets.
            if(Path.GetDirectoryName(oldDir)!=Path.GetDirectoryName(newDir))throw new Exception("Raizes diferentes.");
            Directory.Move(oldDir,newDir);renamed=true;Summary="Instalacao antiga reaproveitada por renomeacao, sem duplicar midia.";
        }
    }
    public void MergeAndReanchor()
    {
        if(!enabled)return;
        if(!renamed){
            foreach(string source in Directory.GetFiles(oldDir,"*",SearchOption.AllDirectories)){
                string relative=source.Substring(oldDir.Length+1),target=Path.Combine(newDir,relative);
                if(File.Exists(target))remaining.Add(new[]{source,target,Hash(source)});
                else{
                    Directory.CreateDirectory(Path.GetDirectoryName(target));
                    File.Move(source,target);moved.Add(new[]{source,target});
                }
            }
            Summary="Instalacoes consolidadas; arquivos novos preservados e arquivos antigos ausentes reaproveitados.";
        }
        string data=Path.Combine(newDir,"Dados");
        if(Directory.Exists(data))foreach(string path in Directory.GetFiles(data,"*.json",SearchOption.TopDirectoryOnly)){
            // No recursive rewriting of archives, credentials, game files or caches.
            string before=File.ReadAllText(path,Encoding.UTF8);object node;
            try{node=json.DeserializeObject(before);}catch{continue;}
            bool changed=false;node=Rewrite(node,ref changed);
            if(!changed)continue;
            string saved=Path.Combine(backup,@"Caminhos\"+Path.GetFileName(path));
            Directory.CreateDirectory(Path.GetDirectoryName(saved));File.Copy(path,saved,false);rewritten[path]=saved;
            File.WriteAllText(path,json.Serialize(node),new UTF8Encoding(true));
        }
    }
    object Rewrite(object node,ref bool changed)
    {
        var text=node as string;
        if(text!=null){
            string value=text;
            if(value.StartsWith(oldDir+"\\",StringComparison.OrdinalIgnoreCase)||value.StartsWith(oldDir+"/",StringComparison.OrdinalIgnoreCase))value=newDir+value.Substring(oldDir.Length);
            else if(value.StartsWith("TarginoLauncher\\",StringComparison.OrdinalIgnoreCase)||value.StartsWith("TarginoLauncher/",StringComparison.OrdinalIgnoreCase))value="TarginoRetroStation"+value.Substring("TarginoLauncher".Length);
            value=value.Replace("{TarginoLauncherDir}","{TarginoRetroStationDir}");
            if(value!=text)changed=true;return value;
        }
        var map=node as Dictionary<string,object>;
        if(map!=null){foreach(string key in new List<string>(map.Keys))map[key]=Rewrite(map[key],ref changed);return map;}
        var array=node as object[];
        if(array!=null){for(int i=0;i<array.Length;i++)array[i]=Rewrite(array[i],ref changed);return array;}
        return node;
    }
    public void RollbackChanges()
    {
        if(CleanupCommitted)return;
        foreach(var item in rewritten)if(File.Exists(item.Value))File.Copy(item.Value,item.Key,true);
        for(int i=moved.Count-1;i>=0;i--){var item=moved[i];if(File.Exists(item[1])&&!File.Exists(item[0])){Directory.CreateDirectory(Path.GetDirectoryName(item[0]));File.Move(item[1],item[0]);}}
    }
    public void UndoRename(){if(!CleanupCommitted&&renamed&&Directory.Exists(newDir)&&!Directory.Exists(oldDir))Directory.Move(newDir,oldDir);}
    public void Commit()
    {
        if(!enabled)return;
        if(!renamed){
            // Preserve differing files once, compressed; never copy identical artwork twice.
            string archive=Path.Combine(backup,"Arquivos-antigos-diferentes.zip");
            var different=new List<string[]>();
            foreach(var item in remaining){
                if(!File.Exists(item[0])||Hash(item[0])!=item[2])throw new Exception("Arquivo antigo mudou durante a migracao; limpeza cancelada.");
                if(!File.Exists(item[1])||Hash(item[1])!=item[2])different.Add(item);
            }
            if(different.Count>0){
                Directory.CreateDirectory(backup);
                using(var zip=ZipFile.Open(archive,ZipArchiveMode.Create))foreach(var item in different)ZipFileExtensions.CreateEntryFromFile(zip,item[0],item[0].Substring(oldDir.Length+1).Replace('\\','/'),CompressionLevel.Optimal);
                using(var zip=ZipFile.OpenRead(archive))foreach(var item in different){var entry=zip.GetEntry(item[0].Substring(oldDir.Length+1).Replace('\\','/'));if(entry==null)throw new Exception("Backup incompleto.");using(var s=entry.Open())if(Hash(s)!=item[2])throw new Exception("Backup divergente.");}
            }
            // All deletions are exact files in the validated old directory, and each
            // either has an identical active copy or a verified archive entry.
            foreach(var item in remaining){
                if(!item[0].StartsWith(oldDir+"\\",StringComparison.OrdinalIgnoreCase))throw new Exception("Alvo fora da pasta antiga.");
                if(Hash(item[0])!=item[2])throw new Exception("Arquivo alterado antes da limpeza.");
            }
            int kept=0;
            CleanupCommitted=true;
            foreach(var item in remaining){try{File.Delete(item[0]);}catch(IOException){kept++;}catch(UnauthorizedAccessException){kept++;}}
            var dirs=new List<string>(Directory.GetDirectories(oldDir,"*",SearchOption.AllDirectories));dirs.Sort((a,b)=>b.Length.CompareTo(a.Length));
            foreach(string dir in dirs)if(Directory.GetFileSystemEntries(dir).Length==0)Directory.Delete(dir,false);
            if(Directory.GetFileSystemEntries(oldDir).Length==0)Directory.Delete(oldDir,false);
            if(kept>0)Summary+=" Alguns arquivos bloqueados permaneceram na pasta antiga; nao foram forcados.";
            else Summary+=" Pasta antiga removida; diferencas preservadas em backup verificado.";
        }
        CleanupCommitted=true;
        Directory.CreateDirectory(backup);
        File.WriteAllText(Path.Combine(backup,"Migracao.json"),json.Serialize(new{Version="1.5.1",Summary=Summary,Old=oldDir,Current=newDir,Renamed=renamed,Date=DateTime.Now.ToString("s")}),new UTF8Encoding(true));
        // Retire only the known command file, after the new entry point exists.
        string root=Path.GetDirectoryName(newDir),oldCommand=Path.Combine(root,"Abrir-TarginoLauncher.cmd");
        if(!Directory.Exists(oldDir)&&File.Exists(Path.Combine(root,"Abrir-TarginoRetroStation.cmd"))&&File.Exists(oldCommand)){
            string command=File.ReadAllText(oldCommand);
            if(command.IndexOf("TarginoLauncher\\Launcher.ps1",StringComparison.OrdinalIgnoreCase)>=0){
                string copy=Path.Combine(backup,"Abrir-TarginoLauncher.cmd");File.Copy(oldCommand,copy,false);
                if(Hash(copy)==Hash(oldCommand))File.Delete(oldCommand);
            }
        }
    }
}
