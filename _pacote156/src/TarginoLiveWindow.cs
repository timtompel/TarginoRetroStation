using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using System.Collections.Generic;

public static class TarginoLiveWindow {
    [StructLayout(LayoutKind.Sequential)] struct Rect { public int L,T,R,B; }
    [DllImport("user32.dll")] static extern bool GetClientRect(IntPtr h,out Rect r);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h,out Rect r);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] static extern bool IsZoomed(IntPtr h);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h,out uint pid);
    [DllImport("user32.dll",SetLastError=true)] static extern bool SetWindowPos(IntPtr h,IntPtr after,int x,int y,int w,int height,uint flags);
    [DllImport("user32.dll")] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
    delegate void WinEventProc(IntPtr hook,uint evt,IntPtr window,int objectId,int childId,uint thread,uint time);
    [DllImport("user32.dll")] static extern IntPtr SetWinEventHook(uint min,uint max,IntPtr module,WinEventProc callback,uint pid,uint thread,uint flags);
    [DllImport("user32.dll")] static extern bool UnhookWinEvent(IntPtr hook);
    [StructLayout(LayoutKind.Sequential)] struct GuiInfo { public uint Size,Flags;public IntPtr Active,Focus,Capture,MenuOwner,MoveSize,Caret;public Rect CaretRect; }
    [DllImport("user32.dll")] static extern bool GetGUIThreadInfo(uint thread,ref GuiInfo info);
    sealed class Watch { public IntPtr Window,Hook;public Geometry Pending;public bool Sizing; }
    static readonly Dictionary<int,Watch> Watches=new Dictionary<int,Watch>();
    static readonly WinEventProc Callback=OnMoveSize;
    public sealed class Geometry { public int Width,Height,X,Y,OuterWidth,OuterHeight; }
    static IntPtr EnterDpi() { try { return SetThreadDpiAwarenessContext(new IntPtr(-4)); } catch(EntryPointNotFoundException) { return IntPtr.Zero; } }
    static void LeaveDpi(IntPtr old) { if(old!=IntPtr.Zero) SetThreadDpiAwarenessContext(old); }
    public static Geometry Measure(IntPtr h,int processId) {
        uint pid; GetWindowThreadProcessId(h,out pid);
        if(h==IntPtr.Zero || pid!=(uint)processId) return null;
        var old=EnterDpi();
        try {
            Rect client,outer;
            if(!GetClientRect(h,out client)||!GetWindowRect(h,out outer)) return null;
            return new Geometry { Width=client.R-client.L,Height=client.B-client.T,X=outer.L,Y=outer.T,OuterWidth=outer.R-outer.L,OuterHeight=outer.B-outer.T };
        } finally { LeaveDpi(old); }
    }
    public static bool CanRemember(IntPtr h,int processId) {
        if(!IsWindowVisible(h)||IsIconic(h)||IsZoomed(h)) return false;
        var old=EnterDpi();
        try {
            var g=Measure(h,processId);if(g==null||g.Width<160||g.Height<120||g.Width>7680||g.Height>4320) return false;
            var bounds=Screen.FromHandle(h).Bounds;
            return !(g.X<=bounds.Left&&g.Y<=bounds.Top&&g.X+g.OuterWidth>=bounds.Right&&g.Y+g.OuterHeight>=bounds.Bottom);
        } finally { LeaveDpi(old); }
    }
    public static bool IsSizing(IntPtr h) {
        uint pid;uint thread=GetWindowThreadProcessId(h,out pid);
        var info=new GuiInfo();info.Size=(uint)Marshal.SizeOf(typeof(GuiInfo));
        return GetGUIThreadInfo(thread,ref info)&&(info.Flags&2)!=0&&info.MoveSize==h;
    }
    public static bool StartWatching(IntPtr h,int processId) {
        uint pid;GetWindowThreadProcessId(h,out pid);if(pid!=(uint)processId) return false;
        Watch existing;
        if(Watches.TryGetValue(processId,out existing)&&existing.Window==h) return existing.Hook!=IntPtr.Zero;
        StopWatching(processId);
        var watch=new Watch { Window=h };
        Watches[processId]=watch;
        // WINEVENT_OUTOFCONTEXT: callback runs in launcher, no DLL injection.
        watch.Hook=SetWinEventHook(0x000A,0x000B,IntPtr.Zero,Callback,(uint)processId,0,0);
        return watch.Hook!=IntPtr.Zero;
    }
    static void OnMoveSize(IntPtr hook,uint evt,IntPtr h,int objectId,int childId,uint thread,uint time) {
        try {
            uint pid;GetWindowThreadProcessId(h,out pid);Watch watch;
            if(!Watches.TryGetValue((int)pid,out watch)||watch.Window!=h||watch.Hook!=hook) return;
            if(evt==0x000A) watch.Sizing=true;
            if(evt==0x000B) {
                watch.Sizing=false;
                if(CanRemember(h,(int)pid)) watch.Pending=Measure(h,(int)pid);
            }
        } catch { /* Never propagate into a native Windows callback. */ }
    }
    public static Geometry TakePending(int processId) {
        Watch watch;if(!Watches.TryGetValue(processId,out watch)) return null;
        var result=watch.Pending;watch.Pending=null;return result;
    }
    public static void StopWatching(int processId) {
        Watch watch;if(!Watches.TryGetValue(processId,out watch)) return;
        if(watch.Hook!=IntPtr.Zero) UnhookWinEvent(watch.Hook);
        Watches.Remove(processId);
    }
    public static string Apply(IntPtr h,int processId,int width,int height,bool center,int x,int y) {
        if(width<160||height<120||width>7680||height>4320) return "invalid-size";
        if(!IsWindowVisible(h)||IsIconic(h)) return "not-visible";
        if(IsZoomed(h)) return "maximized-use-windowed-mode";
        var old=EnterDpi();
        try {
            var current=Measure(h,processId); if(current==null) return "wrong-process";
            int outerW=width+current.OuterWidth-current.Width,outerH=height+current.OuterHeight-current.Height;
            var work=Screen.FromHandle(h).WorkingArea;
            if(outerW>work.Width||outerH>work.Height) return "does-not-fit-monitor";
            if(center) { x=work.Left+(work.Width-outerW)/2; y=work.Top+(work.Height-outerH)/2; }
            else {
                var target=Screen.FromPoint(new System.Drawing.Point(x+outerW/2,y+outerH/2)).WorkingArea;
                if(x<target.Left||y<target.Top||x+outerW>target.Right||y+outerH>target.Bottom) return "position-outside-monitor";
            }
            if(current.Width==width&&current.Height==height&&current.X==x&&current.Y==y) return "unchanged";
            // NOZORDER | NOACTIVATE | NOOWNERZORDER: never steal focus or put Hydra above OBS.
            if(!SetWindowPos(h,IntPtr.Zero,x,y,outerW,outerH,0x214)) return "set-window-pos-failed";
            var actual=Measure(h,processId);
            return actual!=null&&actual.Width==width&&actual.Height==height ? "applied" : "retry";
        } finally { LeaveDpi(old); }
    }
}
