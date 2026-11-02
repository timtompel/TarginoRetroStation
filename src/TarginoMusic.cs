using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Reflection;
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
    [DllImport("winmm.dll", CharSet = CharSet.Unicode)] static extern int mciSendString(string command, StringBuilder result, int length, IntPtr callback);
    [DllImport("winmm.dll", CharSet = CharSet.Unicode)] static extern bool mciGetErrorString(int error, StringBuilder result, int length);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern uint GetShortPathName(string lpszLongPath, StringBuilder lpszShortPath, uint cchBuffer);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window, out uint pid);
    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int key);

    readonly object sync = new object();
    readonly string alias = "targino_music_" + Process.GetCurrentProcess().Id;
    readonly string tempMp3Path = Path.Combine(Path.GetTempPath(), "targino_stream_" + Process.GetCurrentProcess().Id + ".mp3");
    string[] tracks = new string[0], scanned;
    string folder = "";
    int generation, index = -1, failures, volume = 40;
    readonly Random random = new Random(Guid.NewGuid().GetHashCode());
    int[] shuffle = new int[0];
    int shuffleIndex;
    bool ready, opened, paused, usingWmp;
    object wmpPlayer;
    volatile bool disposed;

    public bool Enabled { get; set; }
    public int PlaylistVersion { get; private set; }
    public string LastError { get; private set; }
    public string CurrentTrack { get; private set; }
    public int PlaybackVersion { get; private set; }
    public bool IsPaused { get { return opened && paused; } }
    public bool IsOpen { get { return opened; } }
    public int TrackCount { get { return tracks.Length; } }

    public int Volume
    {
        get { return volume; }
        set
        {
            volume = Math.Max(0, Math.Min(100, value));
            if (opened)
            {
                if (usingWmp) SetWmpVolume(volume);
                else Send("setaudio " + alias + " volume to " + (volume * 10));
            }
        }
    }

    public static bool KeyDown(int key) { return (GetAsyncKeyState(key) & 0x8000) != 0; }
    public static bool MainFocused(IntPtr handle) { return GetForegroundWindow() == handle; }
    public static bool OwnForeground() { uint pid; GetWindowThreadProcessId(GetForegroundWindow(), out pid); return pid == (uint)Process.GetCurrentProcess().Id; }
    public string[] GetTracks() { return (string[])tracks.Clone(); }

    void EnsureWmp()
    {
        if (wmpPlayer != null) return;
        try
        {
            Type t = Type.GetTypeFromProgID("WMPlayer.OCX.7");
            if (t != null)
            {
                wmpPlayer = Activator.CreateInstance(t);
                object settings = wmpPlayer.GetType().InvokeMember("settings", BindingFlags.GetProperty, null, wmpPlayer, null);
                if (settings != null)
                {
                    settings.GetType().InvokeMember("autoStart", BindingFlags.SetProperty, null, settings, new object[] { true });
                    settings.GetType().InvokeMember("volume", BindingFlags.SetProperty, null, settings, new object[] { volume });
                }
            }
        }
        catch { wmpPlayer = null; }
    }

    void SetWmpVolume(int vol)
    {
        try
        {
            if (wmpPlayer == null) return;
            object settings = wmpPlayer.GetType().InvokeMember("settings", BindingFlags.GetProperty, null, wmpPlayer, null);
            if (settings != null) settings.GetType().InvokeMember("volume", BindingFlags.SetProperty, null, settings, new object[] { vol });
        }
        catch { }
    }

    bool OpenWithWmp(string path)
    {
        try
        {
            EnsureWmp();
            if (wmpPlayer == null) return false;
            SetWmpVolume(volume);
            wmpPlayer.GetType().InvokeMember("URL", BindingFlags.SetProperty, null, wmpPlayer, new object[] { path });
            object controls = wmpPlayer.GetType().InvokeMember("controls", BindingFlags.GetProperty, null, wmpPlayer, null);
            if (controls != null) controls.GetType().InvokeMember("play", BindingFlags.InvokeMethod, null, controls, null);
            usingWmp = true;
            return true;
        }
        catch (Exception ex)
        {
            LastError = ex.Message;
            return false;
        }
    }

    int GetWmpPlayState()
    {
        try
        {
            if (wmpPlayer == null) return 0;
            object st = wmpPlayer.GetType().InvokeMember("playState", BindingFlags.GetProperty, null, wmpPlayer, null);
            return st != null ? Convert.ToInt32(st) : 0;
        }
        catch { return 0; }
    }

    void ControlWmp(string method)
    {
        try
        {
            if (wmpPlayer == null) return;
            object controls = wmpPlayer.GetType().InvokeMember("controls", BindingFlags.GetProperty, null, wmpPlayer, null);
            if (controls != null) controls.GetType().InvokeMember(method, BindingFlags.InvokeMethod, null, controls, null);
        }
        catch { }
    }

    string Send(string command)
    {
        var result = new StringBuilder(512);
        int code = mciSendString(command, result, result.Capacity, IntPtr.Zero);
        if (code != 0)
        {
            var error = new StringBuilder(256);
            mciGetErrorString(code, error, error.Capacity);
            LastError = error.ToString();
            return "";
        }
        return result.ToString();
    }

    string PrepareCleanStreamPath(string sourcePath)
    {
        try
        {
            string ext = Path.GetExtension(sourcePath);
            if (ext.Equals(".mp3", StringComparison.OrdinalIgnoreCase))
            {
                byte[] bytes = File.ReadAllBytes(sourcePath);
                int offset = 0;
                // Remove tag ID3v2 pesada (ex: capa de álbum JPEG embutida que trava o mciSendString com erro 277)
                if (bytes.Length > 10 && bytes[0] == 0x49 && bytes[1] == 0x44 && bytes[2] == 0x33)
                {
                    int tagSize = ((bytes[6] & 0x7F) << 21) | ((bytes[7] & 0x7F) << 14) | ((bytes[8] & 0x7F) << 7) | (bytes[9] & 0x7F);
                    if (10 + tagSize < bytes.Length - 1024)
                    {
                        offset = 10 + tagSize;
                    }
                }
                using (var fs = new FileStream(tempMp3Path, FileMode.Create, FileAccess.Write, FileShare.Read))
                {
                    fs.Write(bytes, offset, bytes.Length - offset);
                }
                var sb = new StringBuilder(512);
                if (GetShortPathName(tempMp3Path, sb, (uint)sb.Capacity) > 0 && sb.Length > 0)
                {
                    return sb.ToString();
                }
                return tempMp3Path;
            }
            var shortSb = new StringBuilder(512);
            if (GetShortPathName(sourcePath, shortSb, (uint)shortSb.Capacity) > 0 && shortSb.Length > 0)
            {
                return shortSb.ToString();
            }
        }
        catch { }
        return sourcePath;
    }

    public long Position
    {
        get
        {
            if (!opened) return 0;
            if (usingWmp) return 0;
            long result;
            return long.TryParse(Send("status " + alias + " position"), out result) ? result : 0;
        }
    }

    public void Configure(string path, string[] cached)
    {
        path = (path ?? "").Trim();
        if (!string.Equals(path, folder, StringComparison.OrdinalIgnoreCase))
        {
            Interlocked.Increment(ref generation);
            lock (sync) { ready = false; scanned = null; }
            CloseTrack();
            folder = path;
            tracks = cached == null ? new string[0] : (string[])cached.Clone();
            shuffle = new int[0];
            index = -1;
            failures = 0;
            PlaylistVersion++;
        }
        else if (tracks.Length == 0 && cached != null)
        {
            tracks = (string[])cached.Clone();
            shuffle = new int[0];
            PlaylistVersion++;
        }
        if (path.Length == 0)
        {
            tracks = new string[0];
            PlaylistVersion++;
            return;
        }
        BeginScan(path);
    }

    void BeginScan(string path)
    {
        int request = Interlocked.Increment(ref generation);
        ThreadPool.QueueUserWorkItem(delegate
        {
            var found = new List<string>();
            var queue = new Queue<string>();
            if (Directory.Exists(path)) queue.Enqueue(path);
            while (queue.Count > 0 && !disposed && request == generation)
            {
                string directory = queue.Dequeue();
                try
                {
                    foreach (string file in Directory.GetFiles(directory))
                    {
                        string ext = Path.GetExtension(file);
                        if (ext.Equals(".mp3", StringComparison.OrdinalIgnoreCase) ||
                            ext.Equals(".wav", StringComparison.OrdinalIgnoreCase) ||
                            ext.Equals(".wma", StringComparison.OrdinalIgnoreCase) ||
                            ext.Equals(".m4a", StringComparison.OrdinalIgnoreCase) ||
                            ext.Equals(".flac", StringComparison.OrdinalIgnoreCase))
                        {
                            found.Add(file);
                        }
                    }
                    foreach (string sub in Directory.GetDirectories(directory))
                    {
                        if ((File.GetAttributes(sub) & FileAttributes.ReparsePoint) == 0) queue.Enqueue(sub);
                    }
                }
                catch (IOException) { }
                catch (UnauthorizedAccessException) { }
            }
            found.Sort(StringComparer.CurrentCultureIgnoreCase);
            lock (sync)
            {
                if (!disposed && request == generation)
                {
                    scanned = found.ToArray();
                    ready = true;
                }
            }
        });
    }

    void CommitScan()
    {
        lock (sync)
        {
            if (!ready) return;
            ready = false;
            string current = CurrentTrack;
            bool changed = tracks.Length != scanned.Length;
            if (!changed)
            {
                for (int i = 0; i < tracks.Length; i++)
                {
                    if (!string.Equals(tracks[i], scanned[i], StringComparison.OrdinalIgnoreCase)) { changed = true; break; }
                }
            }
            tracks = scanned;
            scanned = null;
            index = Array.IndexOf(tracks, current);
            if (changed) shuffle = new int[0];
            PlaylistVersion++;
            failures = 0;
        }
    }

    public void Pause()
    {
        if (opened && !paused)
        {
            if (usingWmp) ControlWmp("pause");
            else Send("pause " + alias);
            paused = true;
        }
    }

    public void Tick(bool allowed)
    {
        if (disposed) return;
        CommitScan();
        if (!Enabled || tracks.Length == 0) { CloseTrack(); return; }
        if (!allowed) { Pause(); return; }
        if (!opened) { OpenNext(); return; }
        if (paused)
        {
            if (usingWmp) ControlWmp("play");
            else Send("play " + alias);
            paused = false;
            return;
        }
        if (usingWmp)
        {
            int st = GetWmpPlayState();
            // 1 = Stopped, 8 = MediaEnded, 10 = Ready
            if (st == 1 || st == 8) OpenNext();
        }
        else
        {
            string mode = Send("status " + alias + " mode");
            if (mode == "stopped") OpenNext();
        }
    }

    void OpenNext()
    {
        CloseTrack();
        if (tracks.Length == 0 || failures >= tracks.Length) return;
        index = TakeNextTrack();
        string path = tracks[index];
        if (!File.Exists(path)) { failures++; return; }

        // 1ª tentativa: Motor Windows Media Foundation (WMPlayer.OCX.7) — suporta todos os MP3 (VBR, 320kbps, capas ID3v2, caminhos longos)
        if (OpenWithWmp(path))
        {
            opened = true;
            paused = false;
            CurrentTrack = path;
            PlaybackVersion++;
            failures = 0;
            LastError = "";
            return;
        }

        // 2ª tentativa (Fallback MCI): Stream limpo sem tag ID3v2 pesada e com caminho curto 8.3
        string cleanPath = PrepareCleanStreamPath(path);
        var result = new StringBuilder(512);
        string ext = Path.GetExtension(path);
        string openCmd = ext.Equals(".wav", StringComparison.OrdinalIgnoreCase)
            ? "open \"" + cleanPath + "\" type waveaudio alias " + alias
            : "open \"" + cleanPath + "\" type mpegvideo alias " + alias;

        int code = mciSendString(openCmd, result, result.Capacity, IntPtr.Zero);
        if (code != 0)
        {
            var error = new StringBuilder(256);
            mciGetErrorString(code, error, error.Capacity);
            LastError = error.ToString();
            failures++;
            return;
        }
        usingWmp = false;
        opened = true;
        paused = false;
        CurrentTrack = path;
        PlaybackVersion++;
        failures = 0;
        LastError = "";
        Send("set " + alias + " time format milliseconds");
        Send("setaudio " + alias + " volume to " + (volume * 10));
        Send("play " + alias);
    }

    public void Next() { failures = 0; OpenNext(); }

    int TakeNextTrack()
    {
        if (shuffle.Length != tracks.Length || shuffleIndex >= shuffle.Length)
        {
            shuffle = new int[tracks.Length];
            shuffleIndex = 0;
            for (int i = 0; i < shuffle.Length; i++) shuffle[i] = i;
            for (int i = shuffle.Length - 1; i > 0; i--)
            {
                int j = random.Next(i + 1), swap = shuffle[i];
                shuffle[i] = shuffle[j];
                shuffle[j] = swap;
            }
            if (shuffle.Length > 1 && shuffle[0] == index)
            {
                int swap = shuffle[0];
                shuffle[0] = shuffle[1];
                shuffle[1] = swap;
            }
        }
        return shuffle[shuffleIndex++];
    }

    void CloseTrack()
    {
        if (opened)
        {
            if (usingWmp) ControlWmp("stop");
            else Send("close " + alias);
            opened = false;
            paused = false;
            usingWmp = false;
        }
        CurrentTrack = "";
    }

    public void Dispose()
    {
        disposed = true;
        Interlocked.Increment(ref generation);
        CloseTrack();
        try { if (File.Exists(tempMp3Path)) File.Delete(tempMp3Path); } catch { }
    }
}