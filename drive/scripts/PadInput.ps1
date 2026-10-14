<#
    PadInput.ps1 - reads game controllers, any make, through SDL2.

    FUNCTIONS AND ONE TYPE ONLY. Dot-source it. Used by two things:
      * the Setup Wizard, so it can be driven with a controller
      * PadWatch.ps1, the little background helper that opens the wizard
        when SELECT + START is pressed

    WHY SDL2. It is the library RetroBat's own menu uses to read pads, and a
    copy ships with RetroBat (emulationstation\SDL2.dll). Its "game
    controller" layer gives every pad the same button names - an Xbox pad,
    a PlayStation pad and a Switch pad all report A, B, BACK (select / share
    / minus), START, the bumpers and so on in the same places. XInput alone
    would only have understood Xbox-style pads.

    NOTHING IS HELD OPEN THAT SHOULD NOT BE. The DLL is loaded from whatever
    path the caller gives. The wizard passes the drive's own copy (the
    wizard runs from the drive anyway); the background helper passes the
    copy it keeps on the computer, so it never holds a file open on the
    drive and the drive still ejects.

    [RBPad]::Poll() returns ONE number: a bit per button, OR-ed across every
    connected controller, so it does not matter which pad is picked up.
      bits 0-14   SDL's buttons: 0 A, 1 B, 2 X, 3 Y, 4 BACK, 5 GUIDE,
                  6 START, 7 L3, 8 R3, 9 LB, 10 RB, 11 up, 12 down,
                  13 left, 14 right
      bits 16-19  left stick pushed left, right, up, down
      bits 20-21  right stick pushed up, down
      bits 22-23  left trigger, right trigger

    PURE ASCII on purpose. The C# inside is C# 5, which is what Windows
    PowerShell 5.1 compiles - no ?. and no $"" strings.
#>

if (-not ([System.Management.Automation.PSTypeName]'RBPad').Type) {
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class RBPad
{
    [DllImport("kernel32", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern IntPtr LoadLibrary(string path);

    [StructLayout(LayoutKind.Sequential)]
    struct MSG { public IntPtr hwnd; public uint message; public IntPtr wParam; public IntPtr lParam; public uint time; public int x; public int y; }
    [DllImport("user32.dll")] static extern bool PeekMessage(out MSG m, IntPtr h, uint min, uint max, uint remove);
    [DllImport("user32.dll")] static extern bool TranslateMessage(ref MSG m);
    [DllImport("user32.dll")] static extern IntPtr DispatchMessage(ref MSG m);

    // THE 2026-09-23 FIX. Many pads (Xbox ones especially) reach SDL as
    // Windows "raw input", which only arrives for a thread that is pumping
    // its window messages. The wizard always is - WPF does it - but the
    // background helper has no window, so it saw nothing at all. Pump = true
    // makes Poll() pump them itself. The wizard leaves it false: pumping
    // WPF's messages from inside a timer would be asking for trouble.
    public static bool Pump = false;

    const string L = "SDL2.dll";
    [DllImport(L, CallingConvention = CallingConvention.Cdecl)] static extern int SDL_SetHint([MarshalAs(UnmanagedType.LPStr)] string name, [MarshalAs(UnmanagedType.LPStr)] string value);
    [DllImport(L, CallingConvention = CallingConvention.Cdecl)] static extern int SDL_Init(uint flags);
    [DllImport(L, CallingConvention = CallingConvention.Cdecl)] static extern void SDL_Quit();
    [DllImport(L, CallingConvention = CallingConvention.Cdecl)] static extern void SDL_PumpEvents();
    [DllImport(L, CallingConvention = CallingConvention.Cdecl)] static extern int SDL_NumJoysticks();
    [DllImport(L, CallingConvention = CallingConvention.Cdecl)] static extern int SDL_IsGameController(int index);
    [DllImport(L, CallingConvention = CallingConvention.Cdecl)] static extern int SDL_JoystickGetDeviceInstanceID(int index);
    [DllImport(L, CallingConvention = CallingConvention.Cdecl)] static extern IntPtr SDL_GameControllerOpen(int index);
    [DllImport(L, CallingConvention = CallingConvention.Cdecl)] static extern void SDL_GameControllerClose(IntPtr pad);
    [DllImport(L, CallingConvention = CallingConvention.Cdecl)] static extern int SDL_GameControllerGetAttached(IntPtr pad);
    [DllImport(L, CallingConvention = CallingConvention.Cdecl)] static extern void SDL_GameControllerUpdate();
    [DllImport(L, CallingConvention = CallingConvention.Cdecl)] static extern byte SDL_GameControllerGetButton(IntPtr pad, int button);
    [DllImport(L, CallingConvention = CallingConvention.Cdecl)] static extern short SDL_GameControllerGetAxis(IntPtr pad, int axis);

    static bool ok = false;
    static int polls = 0;
    static Dictionary<int, IntPtr> pads = new Dictionary<int, IntPtr>();
    public static string LastError = "";
    // The left stick as numbers (-32768..32767), from whichever pad is pushing
    // it furthest. Added 2026-10-11 for the wizard's mouse mode (L3), which
    // needs how FAR the stick is pushed, not just which way.
    public static int LX = 0, LY = 0;
    // The right stick the same way (2026-10-14), for the couch mouse's
    // GamePad-screen mode, which moves the pointer with the right stick.
    public static int RX = 0, RY = 0;

    public static bool IsReady { get { return ok; } }
    public static int Count { get { return pads.Count; } }

    public static bool Init(string dllPath)
    {
        if (ok) return true;
        try
        {
            if (LoadLibrary(dllPath) == IntPtr.Zero) { LastError = "could not load " + dllPath; return false; }
            // Keep reading pads when this program is not the window in front.
            // The background helper never has a window at all.
            SDL_SetHint("SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS", "1");
            // And give SDL its own thread for device arrival and raw input,
            // which is exactly what it offers for programs without a window.
            SDL_SetHint("SDL_JOYSTICK_THREAD", "1");
            if (SDL_Init(0x2000u | 0x4000u) != 0) { LastError = "SDL_Init failed"; return false; }
            ok = true;
            Rescan();
            return true;
        }
        catch (Exception e) { LastError = e.Message; return false; }
    }

    static void Rescan()
    {
        int n = SDL_NumJoysticks();
        for (int i = 0; i < n; i++)
        {
            if (SDL_IsGameController(i) == 0) continue;
            int id = SDL_JoystickGetDeviceInstanceID(i);
            if (id < 0 || pads.ContainsKey(id)) continue;
            IntPtr p = SDL_GameControllerOpen(i);
            if (p != IntPtr.Zero) pads[id] = p;
        }
        List<int> gone = new List<int>();
        foreach (KeyValuePair<int, IntPtr> kv in pads)
            if (SDL_GameControllerGetAttached(kv.Value) == 0) gone.Add(kv.Key);
        foreach (int id in gone) { SDL_GameControllerClose(pads[id]); pads.Remove(id); }
    }

    public static int Poll()
    {
        if (!ok) return 0;
        try
        {
            if (Pump)
            {
                MSG m;
                int guard = 0;
                while (guard++ < 200 && PeekMessage(out m, IntPtr.Zero, 0, 0, 1)) { TranslateMessage(ref m); DispatchMessage(ref m); }
            }
            SDL_PumpEvents();
            SDL_GameControllerUpdate();
            polls++;
            if (polls % 20 == 0) Rescan();   // pick up pads plugged in later
            int s = 0;
            int bx = 0, by = 0, cx = 0, cy = 0;
            foreach (IntPtr p in pads.Values)
            {
                for (int b = 0; b <= 14; b++)
                    if (SDL_GameControllerGetButton(p, b) != 0) s |= (1 << b);
                int lx = SDL_GameControllerGetAxis(p, 0), ly = SDL_GameControllerGetAxis(p, 1);
                int rx = SDL_GameControllerGetAxis(p, 2);
                int ry = SDL_GameControllerGetAxis(p, 3);
                if ((long)rx * rx + (long)ry * ry > (long)cx * cx + (long)cy * cy) { cx = rx; cy = ry; }
                int lt = SDL_GameControllerGetAxis(p, 4), rt = SDL_GameControllerGetAxis(p, 5);
                if ((long)lx * lx + (long)ly * ly > (long)bx * bx + (long)by * by) { bx = lx; by = ly; }
                const int dz = 16000;
                if (lx < -dz) s |= 1 << 16;
                if (lx >  dz) s |= 1 << 17;
                if (ly < -dz) s |= 1 << 18;
                if (ly >  dz) s |= 1 << 19;
                if (ry < -dz) s |= 1 << 20;
                if (ry >  dz) s |= 1 << 21;
                if (lt >  dz) s |= 1 << 22;
                if (rt >  dz) s |= 1 << 23;
            }
            LX = bx; LY = by; RX = cx; RY = cy;
            return s;
        }
        catch { return 0; }
    }

    public static void Quit()
    {
        if (!ok) return;
        try
        {
            foreach (IntPtr p in pads.Values) SDL_GameControllerClose(p);
            pads.Clear();
            SDL_Quit();
        }
        catch { }
        ok = false;
    }
}
'@
}

# Button bits, by name, for the scripts that use this.
$script:PadBit = @{
    A = 1; B = 2; X = 4; Y = 8; Back = 16; Guide = 32; Start = 64; L3 = 128; R3 = 256
    LB = 512; RB = 1024
    Up = 2048; Down = 4096; Left = 8192; Right = 16384
    StickLeft = 65536; StickRight = 131072; StickUp = 262144; StickDown = 524288
    RStickUp = 1048576; RStickDown = 2097152
    LT = 4194304; RT = 8388608
}
