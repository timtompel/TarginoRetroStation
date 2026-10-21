using System;
using System.IO;
using System.Security.Cryptography;
public static class AtomicInstall
{
    public static string Hash(string path) {
        using(var sha=SHA256.Create())using(var input=File.OpenRead(path))return BitConverter.ToString(sha.ComputeHash(input)).Replace("-","").ToLowerInvariant();
    }
    public static void Write(Stream input,string destination,string expectedHash) {
        string temporary=destination+"."+Guid.NewGuid().ToString("N")+".installing";
        try {
            using(var output=new FileStream(temporary,FileMode.CreateNew,FileAccess.Write,FileShare.None)){input.CopyTo(output);output.Flush(true);}
            if(!Hash(temporary).Equals(expectedHash,StringComparison.OrdinalIgnoreCase))throw new IOException("Hash invalido: "+Path.GetFileName(destination));
            if(File.Exists(destination))File.Replace(temporary,destination,null);else File.Move(temporary,destination);
        } finally {if(File.Exists(temporary))File.Delete(temporary);}
    }
    public static void AssertLocalParents(string root,string destination) {
        root=Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar);destination=Path.GetFullPath(destination);
        if(!destination.StartsWith(root+Path.DirectorySeparatorChar,StringComparison.OrdinalIgnoreCase))throw new IOException("Destino fora da instalacao.");
        string current=Path.GetDirectoryName(destination);
        while(current!=null && current.Length>=root.Length) {
            if(Directory.Exists(current)&&(File.GetAttributes(current)&FileAttributes.ReparsePoint)!=0)throw new IOException("Destino usa link de pasta.");
            if(current.Equals(root,StringComparison.OrdinalIgnoreCase))break;current=Path.GetDirectoryName(current);
        }
        if(File.Exists(destination)&&(File.GetAttributes(destination)&FileAttributes.ReparsePoint)!=0)throw new IOException("Destino usa link de arquivo.");
    }
}
