// Native-code-profile-gated direct launch adapter. Only our new process is modified.
// No native executable, core, ROM or emulator configuration is edited on disk.
using System;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;
using System.Security.Cryptography;
using System.Runtime.InteropServices;
using System.ComponentModel;
using System.Diagnostics;
using System.Collections.Generic;
using System.Web.Script.Serialization;
public static class HydraDirectBridge {
    public const string SupportedHash="5C29156BB7907FD793E29923E30A73663BA7C30729AF88228D041C4A91A49BAA";
    public const string AdapterVersion="1.4.0-rc2";
    const string SupportedCodeHash="0DE3F8DC41015CBECAF429CD378C5A0D553DBFA9B4C7C7CA2EC4CB2C3550F95E";
    const string OfficialCodeHash="C7CC95ED017F2F42FF9E0DCEBF9B93E3A0EA55FD494472203335A409E40EFD48";
    public sealed class Patch {public uint Rva;public byte[] Before,After;public bool Code;}
    public sealed class Plan {public string System,Choice;public Patch[] Patches;}
    [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)] struct Startup {
        public int cb; public string reserved,desktop,title; public int x,y,xSize,ySize,xCount,yCount,fill,flags;
        public short show,reservedSize; public IntPtr reservedPtr,input,output,error;
    }
    [StructLayout(LayoutKind.Sequential)] struct Info {public IntPtr process,thread;public uint pid,tid;}
    [StructLayout(LayoutKind.Sequential)] struct Basic {public IntPtr reserved1,peb,reserved2,reserved3,pid,reserved4;}
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool CreateProcessW(string app,StringBuilder args,IntPtr pa,IntPtr ta,bool inherit,uint flags,IntPtr env,string cwd,ref Startup startup,out Info info);
    [DllImport("ntdll.dll")] static extern int NtQueryInformationProcess(IntPtr process,int kind,ref Basic basic,int size,out int needed);
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool ReadProcessMemory(IntPtr process,IntPtr at,byte[] data,UIntPtr size,out UIntPtr read);
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool WriteProcessMemory(IntPtr process,IntPtr at,byte[] data,UIntPtr size,out UIntPtr written);
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool VirtualProtectEx(IntPtr process,IntPtr at,UIntPtr size,uint protect,out uint old);
    [DllImport("kernel32.dll",SetLastError=true)] static extern uint ResumeThread(IntPtr thread);
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool FlushInstructionCache(IntPtr process,IntPtr at,UIntPtr size);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
    [DllImport("kernel32.dll")] static extern bool TerminateProcess(IntPtr handle,uint code);
    static readonly JavaScriptSerializer Json=new JavaScriptSerializer();
    static string Hash(byte[] data){using(var sha=SHA256.Create())return BitConverter.ToString(sha.ComputeHash(data)).Replace("-","");}
    public static bool IsSupported(string exe){try{LocateStartup(File.ReadAllBytes(exe));return true;}catch{return false;}}
    // Read-only observation of the known native profile. A loaded DLL is not
    // evidence of a loaded game: PS2 can retain its library after retro_unload_game.
    public sealed class ReturnObserver {
        readonly Process process; readonly long imageBase; long application;
        [StructLayout(LayoutKind.Sequential)] struct ThreadBasic {
            public int status; public IntPtr teb,pid,tid,affinity; public int priority,basePriority;
        }
        [DllImport("kernel32.dll",SetLastError=true)] static extern IntPtr OpenThread(uint access,bool inherit,uint id);
        [DllImport("ntdll.dll")] static extern int NtQueryInformationThread(IntPtr thread,int kind,ref ThreadBasic data,int size,IntPtr needed);
        public ReturnObserver(Process process,string exe){
            LocateStartup(File.ReadAllBytes(exe));this.process=process;
            imageBase=process.MainModule.BaseAddress.ToInt64();
            // This stack anchor is specific to the two whole-code-hash profiles.
            byte[] anchor=Read(imageBase+0x427e,5);
            if(anchor==null||anchor[0]!=0xe8||BitConverter.ToInt32(anchor,1)!=0xd82d)throw new Exception("Perfil de retorno nativo desconhecido.");
        }
        byte[] Read(long at,int count){
            if(at<0x10000||at>0x00007fffffffffffL)return null;
            byte[] data=new byte[count];UIntPtr done;
            return ReadProcessMemory(process.Handle,new IntPtr(at),data,(UIntPtr)count,out done)&&done.ToUInt64()==(ulong)count?data:null;
        }
        long Pointer(long at){byte[] data=Read(at,8);return data==null?0:BitConverter.ToInt64(data,0);}
        bool LocateApplication(){
            foreach(ProcessThread thread in process.Threads){
                IntPtr handle=OpenThread(0x40,false,(uint)thread.Id);if(handle==IntPtr.Zero)continue;
                try{
                    var info=new ThreadBasic();
                    if(NtQueryInformationThread(handle,0,ref info,Marshal.SizeOf(typeof(ThreadBasic)),IntPtr.Zero)!=0)continue;
                    byte[] tib=Read(info.teb.ToInt64(),24);if(tib==null)continue;
                    long top=BitConverter.ToInt64(tib,8),bottom=BitConverter.ToInt64(tib,16);
                    int count=(int)Math.Min(65536,top-bottom);if(count<0xa00)continue;
                    byte[] stack=Read(top-count,count);if(stack==null)continue;
                    for(int n=0;n<=count-0xa00;n+=8){
                        if(BitConverter.ToInt64(stack,n)!=imageBase+0x4283)continue;
                        long candidate=top-count+n+0x30;
                        // Main's App object must contain a parsed --boot system and ROM.
                        long systemLength=Pointer(candidate+0x870),romLength=Pointer(candidate+0x890);
                        if(systemLength<1||systemLength>32||romLength<1||romLength>32767)continue;
                        if(application!=0&&application!=candidate)return false;
                        application=candidate;
                    }
                }finally{CloseHandle(handle);}
            }
            return application!=0;
        }
        // -1 = unknown (never close on it), 0 = no game, 1 = loaded game.
        public int ReadGameState(){
            try{
                if(application==0&&!LocateApplication())return -1;
                long backend=Pointer(application+0x3b8);if(backend==0)return 0;
                long vtable=Pointer(backend),getter=Pointer(vtable+0x108);
                if(getter<imageBase||getter>=imageBase+0x290000)return -1;
                byte[] code=Read(getter,12);if(code==null)return -1;
                int field;
                if(code[0]==0x0f&&code[1]==0xb6&&code[2]==0x81&&code[7]==0xc3)field=BitConverter.ToInt32(code,3);
                else if(code[0]==0x0f&&code[1]==0xb6&&code[2]==0x41&&code[4]==0xc3)field=(sbyte)code[3];
                else return -1;
                if(field<0||field>0x10000)return -1;
                byte[] state=Read(backend+field,1);return state!=null&&state[0]<=1?state[0]:-1;
            }catch{return -1;}
        }
    }
    public static string GetCompatibilityReason(string exe,string system){
        try{Prepare(exe,system,system=="ps2"?"opengl":"aes");return "";}catch(Exception error){return error.Message;}
    }
    static int SectionTable(byte[] data,out int count){
        if(data.Length<256||data[0]!=77||data[1]!=90)throw new Exception("Executavel Hydra invalido.");
        int pe=BitConverter.ToInt32(data,0x3c);
        if(pe<64||pe>data.Length-24||BitConverter.ToUInt32(data,pe)!=0x4550||BitConverter.ToUInt16(data,pe+4)!=0x8664)throw new Exception("Hydra nao e um executavel Windows x64 reconhecido.");
        count=BitConverter.ToUInt16(data,pe+6);int optional=BitConverter.ToUInt16(data,pe+20);
        if(optional<112||pe+24>data.Length-optional||BitConverter.ToUInt16(data,pe+24)!=0x20b||count<1||count>96)throw new Exception("Cabecalho PE invalido.");
        int table=pe+24+optional;if(table>data.Length-count*40)throw new Exception("Secoes PE incompletas.");return table;
    }
    static uint LocateStartup(byte[] data){
        int count,table=SectionTable(data,out count),foundSection=-1;
        for(int i=0;i<count;i++){
            int at=table+i*40;string name=Encoding.ASCII.GetString(data,at,8).TrimEnd('\0');
            if(name!=".text")continue;if(foundSection>=0)throw new Exception("Codigo nativo ambiguo.");foundSection=at;
        }
        if(foundSection<0)throw new Exception("Codigo nativo do Hydra nao identificado.");
        uint raw=BitConverter.ToUInt32(data,foundSection+20),size=BitConverter.ToUInt32(data,foundSection+16);
        if((BitConverter.ToUInt32(data,foundSection+36)&0x20000000)==0||raw>data.Length||size>data.Length-raw||size<22)throw new Exception("Secao de codigo invalida.");
        byte[] code=new byte[(int)size];Buffer.BlockCopy(data,(int)raw,code,0,code.Length);
        // Whole-file changes to timestamps, icons, resources or signatures are not ABI changes.
        // Unknown executable CODE is still rejected; a short byte pattern alone is insufficient.
        string codeHash=Hash(code);
        if(codeHash!=SupportedCodeHash&&codeHash!=OfficialCodeHash)throw new Exception("O codigo nativo desta compilacao ainda nao corresponde a um perfil de abertura direta validado.");
        byte[] signature={0xc6,0x87,0x49,0x09,0,0,1,0xc6,0x87,0x93,0x09,0,0,1,0x48,0x83,0xbf,0x70,0x08,0,0,0};
        int found=-1;
        for(int i=0;i<=code.Length-signature.Length;i++){
            bool same=true;for(int j=0;j<signature.Length;j++)if(code[i+j]!=signature[j]){same=false;break;}
            if(!same)continue;if(found>=0)throw new Exception("Assinatura de abertura direta ambigua.");found=i;
        }
        if(found<0)throw new Exception("Assinatura de abertura direta nao identificada.");
        return BitConverter.ToUInt32(data,foundSection+12)+(uint)found;
    }
    static void Require(bool ok,string action){if(!ok)throw new Win32Exception(Marshal.GetLastWin32Error(),action);}
    static bool Equal(byte[] a,byte[] b){if(a.Length!=b.Length)return false;for(int i=0;i<a.Length;i++)if(a[i]!=b[i])return false;return true;}
    static string Quote(string value){
        if(value==null||value.IndexOfAny(new char[]{'"','\r','\n','\0'})>=0)throw new ArgumentException("Argumento de caminho invalido.");
        return "\""+value+"\"";
    }
    static uint ToRva(byte[] data,int offset){
        int pe=BitConverter.ToInt32(data,0x3c),count=BitConverter.ToUInt16(data,pe+6),table=pe+24+BitConverter.ToUInt16(data,pe+20);
        for(int i=0;i<count;i++){
            int section=table+i*40;uint raw=BitConverter.ToUInt32(data,section+20),size=BitConverter.ToUInt32(data,section+16);
            if(offset>=raw&&offset<raw+size)return BitConverter.ToUInt32(data,section+12)+(uint)offset-raw;
        }
        throw new Exception("Manifesto fora das secoes mapeadas do Hydra.");
    }
    static int ToOffset(byte[] data,uint rva){
        int pe=BitConverter.ToInt32(data,0x3c),count=BitConverter.ToUInt16(data,pe+6),table=pe+24+BitConverter.ToUInt16(data,pe+20);
        for(int i=0;i<count;i++){
            int section=table+i*40;uint start=BitConverter.ToUInt32(data,section+12),size=BitConverter.ToUInt32(data,section+16);
            if(rva>=start&&rva<start+size)return (int)(BitConverter.ToUInt32(data,section+20)+rva-start);
        }
        throw new Exception("Assinatura fora das secoes mapeadas do Hydra.");
    }
    static Patch Flag(byte[] data,uint rva,byte[] expected){
        int offset=ToOffset(data,rva);byte[] actual=new byte[expected.Length];Buffer.BlockCopy(data,offset,actual,0,actual.Length);
        if(!Equal(actual,expected))throw new Exception("Assinatura de inicializacao do Hydra nao reconhecida.");
        byte[] replacement=(byte[])expected.Clone();replacement[replacement.Length-1]=0;
        return new Patch{Rva=rva,Before=expected,After=replacement,Code=true};
    }
    public static Plan Prepare(string exe,string system,string choice){
        if(IntPtr.Size!=8)throw new Exception("A abertura direta requer o launcher de 64 bits.");
        if(system!="ps2"&&system!="neogeo")throw new ArgumentException("Sistema nao suportado pelo adaptador direto.");
        string renderer=null;
        if(system=="ps2"){
            renderer=choice=="software"?"Software (HW)":choice=="hardware"||choice=="vulkan"?"Vulkan":choice=="opengl"?"OpenGL":null;
            if(renderer==null)throw new ArgumentException("Renderizador invalido.");
        }else if(choice!="aes"&&choice!="mvs")throw new ArgumentException("Modo Neo Geo invalido.");
        byte[] data=File.ReadAllBytes(exe);
        uint startupRva=LocateStartup(data);
        Match manifest=null;
        foreach(Match match in Regex.Matches(Encoding.ASCII.GetString(data),"(?s)\\{\\s*\"manifest_version\"[^\\x00]+")){
            if(Regex.IsMatch(match.Value,"\"id\"\\s*:\\s*\""+system+"\"")){
                if(manifest!=null)throw new Exception("Manifesto duplicado.");manifest=match;
            }
        }
        if(manifest==null)throw new Exception("Manifesto do sistema nao encontrado.");
        byte[] before=new byte[manifest.Length];Buffer.BlockCopy(data,manifest.Index,before,0,before.Length);
        var parsed=Json.Deserialize<Dictionary<string,object>>(Encoding.UTF8.GetString(before));
        string expectedLibrary=system=="ps2"?"pcsx2_libretro.dll":"geolith_libretro.dll";
        string expectedPrefix=system=="ps2"?"pcsx2":"geolith";
        if(!parsed.ContainsKey("library")||!parsed.ContainsKey("libretro")||!parsed.ContainsKey("backend")||
            (string)parsed["library"]!=expectedLibrary||(string)parsed["libretro"]!=expectedPrefix||(string)parsed["backend"]!="core")throw new Exception("Estrutura do core diferente da estrutura validada.");
        var defaults=parsed["defaults"] as Dictionary<string,object>;
        if(defaults==null)throw new Exception("Padroes de core invalidos.");
        if(system=="ps2"){
            defaults["renderer"]=renderer;
            // OpenGL/software must not depend on Vulkan availability. The real Vulkan
            // probe is kept intact for Vulkan and for every other native system.
            if(choice!="hardware"&&choice!="vulkan")parsed["requires"]="";
        }
        else {defaults["system_type"]=choice;defaults["unibios_hw"]=choice;}
        byte[] compact=Encoding.UTF8.GetBytes(Json.Serialize(parsed));
        if(compact.Length>before.Length)throw new Exception("Nao ha espaco reservado para as opcoes do core.");
        byte[] after=new byte[before.Length];for(int i=0;i<after.Length;i++)after[i]=32;Buffer.BlockCopy(compact,0,after,0,compact.Length);
        // Parse it again before creating a process; also validates UTF-8 and JSON padding.
        Json.DeserializeObject(Encoding.UTF8.GetString(after));
        return new Plan{System=system,Choice=choice,Patches=new Patch[]{
            new Patch{Rva=ToRva(data,manifest.Index),Before=before,After=after,Code=false},
            Flag(data,startupRva,new byte[]{0xc6,0x87,0x49,0x09,0,0,1}),
            Flag(data,startupRva+7,new byte[]{0xc6,0x87,0x93,0x09,0,0,1})}};
    }
    static void Apply(IntPtr process,long imageBase,Patch patch){
        IntPtr at=new IntPtr(imageBase+patch.Rva);byte[] current=new byte[patch.Before.Length];UIntPtr done;
        Require(ReadProcessMemory(process,at,current,(UIntPtr)current.Length,out done)&&done.ToUInt64()==(ulong)current.Length,"Ler assinatura de memoria");
        if(!Equal(current,patch.Before))throw new Exception("A memoria do Hydra nao corresponde a versao validada.");
        uint old,ignored;Require(VirtualProtectEx(process,at,(UIntPtr)patch.After.Length,4,out old),"Preparar memoria de inicializacao");
        try{Require(WriteProcessMemory(process,at,patch.After,(UIntPtr)patch.After.Length,out done)&&done.ToUInt64()==(ulong)patch.After.Length,"Aplicar opcoes de inicializacao");}
        finally{Require(VirtualProtectEx(process,at,(UIntPtr)patch.After.Length,old,out ignored),"Restaurar protecao de memoria");}
        if(patch.Code)Require(FlushInstructionCache(process,at,(UIntPtr)patch.After.Length),"Sincronizar inicializacao");
        Require(ReadProcessMemory(process,at,current,(UIntPtr)current.Length,out done)&&done.ToUInt64()==(ulong)current.Length,"Verificar memoria de inicializacao");
        if(!Equal(current,patch.After))throw new Exception("As opcoes de memoria nao foram confirmadas.");
    }
    public static Process Start(string exe,string system,string rom,string choice){return StartCapture(exe,system,rom,choice,null,0);}
    public static Process StartCapture(string exe,string system,string rom,string choice,string capture,int frames){
        exe=Path.GetFullPath(exe);rom=Path.GetFullPath(rom);
        if(!File.Exists(rom))throw new FileNotFoundException("ROM nao encontrada.",rom);
        if(system=="neogeo"&&!string.Equals(Path.GetExtension(rom),".neo",StringComparison.OrdinalIgnoreCase))throw new Exception("AES/MVS requer uma ROM .neo.");
        var plan=Prepare(exe,system,choice);Info info=new Info();bool resumed=false;Process native=null;
        string command=Quote(exe)+" --boot "+system+" "+Quote(rom);
        if(capture!=null){if(frames<1||frames>6000)throw new ArgumentException("Limite de captura invalido.");command+=" --screenshot "+Quote(Path.GetFullPath(capture))+" --frames "+frames;}
        try{
            var startup=new Startup();startup.cb=Marshal.SizeOf(typeof(Startup));
            Require(CreateProcessW(exe,new StringBuilder(command),IntPtr.Zero,IntPtr.Zero,false,4,IntPtr.Zero,Path.GetDirectoryName(exe),ref startup,out info),"Criar processo Hydra");
            var basic=new Basic();int needed;
            if(NtQueryInformationProcess(info.process,0,ref basic,Marshal.SizeOf(typeof(Basic)),out needed)!=0)throw new Exception("Nao foi possivel localizar a imagem do Hydra.");
            byte[] image=new byte[8];UIntPtr done;
            Require(ReadProcessMemory(info.process,IntPtr.Add(basic.peb,0x10),image,(UIntPtr)8,out done)&&done.ToUInt64()==8,"Ler endereco da imagem Hydra");
            foreach(var patch in plan.Patches)Apply(info.process,BitConverter.ToInt64(image,0),patch);
            native=Process.GetProcessById((int)info.pid);
            // Hold a process handle before ResumeThread, including for immediate-load failures.
            IntPtr keepAlive=native.Handle;
            if(ResumeThread(info.thread)==0xffffffff)throw new Win32Exception(Marshal.GetLastWin32Error());
            resumed=true;return native;
        }catch{if(!resumed&&info.process!=IntPtr.Zero)TerminateProcess(info.process,1);if(native!=null)native.Dispose();throw;}
        finally{if(info.thread!=IntPtr.Zero)CloseHandle(info.thread);if(info.process!=IntPtr.Zero)CloseHandle(info.process);}
    }
}
