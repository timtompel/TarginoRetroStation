using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

public sealed class TarginoDeveloperGate
{
    long started = -1;
    bool latched;
    public bool Update(bool focused, bool shift, bool f10, long milliseconds)
    {
        if (!shift || !f10) { started = -1; latched = false; return false; }
        if (!focused) { started = -1; return false; }
        if (latched) return false;
        if (started < 0) started = milliseconds;
        if (milliseconds - started < 5000) return false;
        latched = true; return true;
    }
}

public sealed class TarginoMusicPlayer : IDisposable
{
    [DllImport("winmm.dll", CharSet=CharSet.Unicode)] static extern int mciSendString(string command, StringBuilder result, int length, IntPtr callback);
    [DllImport("winmm.dll", CharSet=CharSet.Unicode)] static extern bool mciGetErrorString(int error, StringBuilder result, int length);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window, out uint pid);
    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int key);
    readonly object sync = new object();
    readonly string alias = "targino_music_" + Process.GetCurrentProcess().Id;
    string[] tracks = new string[0], scanned;
    string folder = "";
    int generation, index = -1, failures, volume = 40;
    readonly Random random = new Random(Guid.NewGuid().GetHashCode());
    int[] shuffle = new int[0]; int shuffleIndex;
    bool ready, opened, paused;
    volatile bool disposed;
    public bool Enabled {get;set;}
    public int PlaylistVersion {get;private set;}
    public string LastError {get;private set;}
    public string CurrentTrack {get;private set;}
    public int PlaybackVersion {get;private set;}
    public bool IsPaused {get{return opened && paused;}}
    public bool IsOpen {get{return opened;}}
    public int TrackCount {get{return tracks.Length;}}
    public int Volume {
        get{return volume;}
        set{volume=Math.Max(0,Math.Min(100,value));if(opened)Send("setaudio "+alias+" volume to "+(volume*10));}
    }
    public static bool KeyDown(int key){return (GetAsyncKeyState(key)&0x8000)!=0;}
    public static bool MainFocused(IntPtr handle){return GetForegroundWindow()==handle;}
    public static bool OwnForeground(){uint pid;GetWindowThreadProcessId(GetForegroundWindow(),out pid);return pid==(uint)Process.GetCurrentProcess().Id;}
    public string[] GetTracks(){return (string[])tracks.Clone();}
    string Send(string command)
    {
        var result=new StringBuilder(512);
        int code=mciSendString(command,result,result.Capacity,IntPtr.Zero);
        if(code!=0){var error=new StringBuilder(256);mciGetErrorString(code,error,error.Capacity);LastError=error.ToString();return "";}
        return result.ToString();
    }
    public long Position {
        get{long result;return opened&&long.TryParse(Send("status "+alias+" position"),out result)?result:0;}
    }
    public void Configure(string path,string[] cached)
    {
        path=path??"";
        if(!string.Equals(path,folder,StringComparison.OrdinalIgnoreCase)){
            Interlocked.Increment(ref generation);
            lock(sync){ready=false;scanned=null;}
            CloseTrack();folder=path;tracks=cached==null?new string[0]:(string[])cached.Clone();shuffle=new int[0];index=-1;failures=0;PlaylistVersion++;
        }else if(tracks.Length==0 && cached!=null){tracks=(string[])cached.Clone();shuffle=new int[0];PlaylistVersion++;}
        if(path.Length==0){tracks=new string[0];PlaylistVersion++;return;}
        BeginScan(path);
    }
    void BeginScan(string path)
    {
        int request=Interlocked.Increment(ref generation);
        ThreadPool.QueueUserWorkItem(delegate {
            var found=new List<string>();var queue=new Queue<string>();queue.Enqueue(path);
            while(queue.Count>0 && !disposed && request==generation){
                string directory=queue.Dequeue();
                try{
                    foreach(string file in Directory.GetFiles(directory)){
                        string extension=Path.GetExtension(file);
                        if(extension.Equals(".mp3",StringComparison.OrdinalIgnoreCase)||extension.Equals(".wav",StringComparison.OrdinalIgnoreCase))found.Add(file);
                    }
                    foreach(string sub in Directory.GetDirectories(directory))if((File.GetAttributes(sub)&FileAttributes.ReparsePoint)==0)queue.Enqueue(sub);
                }catch(IOException){}catch(UnauthorizedAccessException){}
            }
            found.Sort(StringComparer.CurrentCultureIgnoreCase);
            lock(sync){if(!disposed && request==generation){scanned=found.ToArray();ready=true;}}
        });
    }
    void CommitScan()
    {
        lock(sync){
            if(!ready)return;ready=false;
            string current=CurrentTrack;
            bool changed=tracks.Length!=scanned.Length;
            if(!changed)for(int i=0;i<tracks.Length;i++)if(!string.Equals(tracks[i],scanned[i],StringComparison.OrdinalIgnoreCase)){changed=true;break;}
            tracks=scanned;scanned=null;index=Array.IndexOf(tracks,current);
            if(changed)shuffle=new int[0];
            PlaylistVersion++;failures=0;
        }
    }
    public void Pause()
    {
        if(opened&&!paused){Send("pause "+alias);paused=true;}
    }
    public void Tick(bool allowed)
    {
        if(disposed)return;CommitScan();
        if(!Enabled||tracks.Length==0){CloseTrack();return;}
        if(!allowed){Pause();return;}
        if(!opened){OpenNext();return;}
        if(paused){Send("play "+alias);paused=false;return;}
        string mode=Send("status "+alias+" mode");
        if(mode=="stopped")OpenNext();
    }
    void OpenNext()
    {
        CloseTrack();
        // One failed track per timer tick avoids blocking the UI on damaged files.
        if(tracks.Length==0||failures>=tracks.Length)return;
        index=TakeNextTrack();string path=tracks[index];
        if(!File.Exists(path)){failures++;return;}
        var result=new StringBuilder(512);
        int code=mciSendString("open \""+path+"\" type mpegvideo alias "+alias,result,result.Capacity,IntPtr.Zero);
        if(code!=0){var error=new StringBuilder(256);mciGetErrorString(code,error,error.Capacity);LastError=error.ToString();failures++;return;}
        opened=true;paused=false;CurrentTrack=path;PlaybackVersion++;failures=0;LastError="";
        Send("set "+alias+" time format milliseconds");
        Send("setaudio "+alias+" volume to "+(volume*10));
        Send("play "+alias);
    }
    public void Next(){failures=0;OpenNext();}
    int TakeNextTrack()
    {
        if(shuffle.Length!=tracks.Length||shuffleIndex>=shuffle.Length){
            shuffle=new int[tracks.Length];shuffleIndex=0;
            for(int i=0;i<shuffle.Length;i++)shuffle[i]=i;
            for(int i=shuffle.Length-1;i>0;i--){int j=random.Next(i+1),swap=shuffle[i];shuffle[i]=shuffle[j];shuffle[j]=swap;}
            // Every track plays once per round; avoid repeating across rounds.
            if(shuffle.Length>1&&shuffle[0]==index){int swap=shuffle[0];shuffle[0]=shuffle[1];shuffle[1]=swap;}
        }
        return shuffle[shuffleIndex++];
    }
    void CloseTrack()
    {
        if(opened){Send("close "+alias);opened=false;paused=false;}
        CurrentTrack="";
    }
    public void Dispose(){disposed=true;Interlocked.Increment(ref generation);CloseTrack();}
}
