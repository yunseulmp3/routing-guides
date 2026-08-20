<#
=====================================================================
 윤슬 라우팅 닥터 (Routing Doctor) - 진단 전용
 ---------------------------------------------------------------
 * 이 프로그램은 아무것도 바꾸지 않습니다. 읽기만 합니다.
 * 윈도우 오디오 장치 상태를 훑어서 "윤슬 표준 라우팅"과 어긋난
   부분을 찾아 알려줍니다.
 * 결과는 화면 요약 + 텍스트 로그 파일로 남습니다.

 사용법
   powershell -NoProfile -ExecutionPolicy Bypass -File .\routing-doctor.ps1
   (또는 같은 폴더의 "진단하기.cmd" 더블클릭)

 옵션
   -OutFile <경로>   로그 저장 위치 지정 (기본: 바탕화면)
   -NoPause          끝나고 키 입력 대기 없이 종료
   -FromDump <경로>  실제 PC 대신 예전 덤프 파일을 다시 분석 (테스트용)
   -Setup <모드>     Auto(기본) / Single(단컴) / Game(투컴-게임PC) / Stream(투컴-방송PC)
   -Compare <경로>   예전 진단 결과 파일과 지금 상태를 비교해서 '무엇이 바뀌었는지' 표시
=====================================================================
#>
param(
    [switch]$NoPause,
    [string]$OutFile,
    [string]$FromDump,
    [string]$Compare,
    [ValidateSet('Auto','Single','Game','Stream')]
    [string]$Setup = 'Auto'
)

$ErrorActionPreference = 'Continue'
$ScriptVersion = '2.2'

# =====================================================================
# 0. 윤슬 표준 정의 (여기만 고치면 판정 기준이 바뀝니다)
# =====================================================================
$YS = [ordered]@{
    # 재생(Playback) 쪽 표준 이름 - 앱별 출력 지정 대상
    RequiredRenderNames  = @('Chrome', 'Discord')
    # 녹음(Capture) 쪽 표준 이름 - REAPER 처리된 마이크가 돌아오는 입구.
    # REAPER는 ASIO로 하드웨어 채널에 직접 출력하므로, 윈도우 재생 쪽에는 MIC가 없는 것이 정상.
    RequiredCaptureNames = @('MIC')
    # 있으면 좋은 이름 (없어도 문제는 아님)
    OptionalRenderNames  = @('PC', 'Syncroom', 'Karaoke', '스피커', 'Speaker')
    OptionalCaptureNames = @('Karaoke', 'Syncroom Mic')
    # 볼륨이 이 아래면 주의
    LowVolumeThreshold  = 0.15
}

# 제조사 판별표 (하드웨어 ID 우선, 없으면 이름으로)
$VendorById = @(
    @{ Id = 'VID_2A39'; Brand = 'RME';                    Mixer = 'TotalMix FX'; Grade = 'A' }
    @{ Id = 'VID_2708'; Brand = 'Audient';                Mixer = 'iD 믹서 앱';        ForceRate = 44100; Grade = 'B' }
    @{ Id = 'VID_1235'; Brand = 'Focusrite';              Mixer = 'Focusrite Control' }
    @{ Id = 'VID_0499'; Brand = 'Yamaha / Steinberg';     Mixer = 'dspMixFx / Yamaha 유틸' }
    @{ Id = 'VID_1397'; Brand = 'BEHRINGER 계열';         Mixer = '제조사 유틸' }
    @{ Id = 'VID_20B1'; Brand = 'XMOS 계열 (Topping 등)'; Mixer = '제조사 전용 앱' }
    @{ Id = 'VID_152A'; Brand = 'Thesycon 계열';          Mixer = '제조사 전용 앱' }
    @{ Id = 'VID_194F'; Brand = 'PreSonus';               Mixer = 'UC Surface' }
    @{ Id = 'VID_0582'; Brand = 'Roland / Edirol';        Mixer = 'Roland 유틸' }
    @{ Id = 'VID_1686'; Brand = 'Zoom';                   Mixer = 'Zoom 유틸' }
    @{ Id = 'VID_0FD9'; Brand = 'Elgato';                 Mixer = 'Wave Link' }
    @{ Id = 'VID_1B1C'; Brand = 'Corsair / Elgato';       Mixer = '제조사 앱' }
    @{ Id = 'VID_17CC'; Brand = 'Native Instruments';     Mixer = 'NI 컨트롤 패널' }
    @{ Id = 'VID_0763'; Brand = 'M-Audio';                Mixer = '제조사 유틸' }
    @{ Id = 'VID_0644'; Brand = 'TASCAM';                 Mixer = 'TASCAM 설정 패널' }
    @{ Id = 'VID_041E'; Brand = 'Creative Sound Blaster'; Mixer = 'Creative App / Sound Blaster Command'; Card = $true }
    @{ Id = 'VEN_1102'; Brand = 'Creative Sound Blaster'; Mixer = 'Creative App / Sound Blaster Command'; Card = $true }
)
$VendorByName = @(
    @{ Name = 'RME';            Brand = 'RME';               Mixer = 'TotalMix FX'; Grade = 'A' }
    @{ Name = 'Babyface';       Brand = 'RME';               Mixer = 'TotalMix FX'; Grade = 'A' }
    @{ Name = 'Fireface';       Brand = 'RME';               Mixer = 'TotalMix FX'; Grade = 'A' }
    @{ Name = 'Audient';        Brand = 'Audient';           Mixer = 'iD 믹서 앱';  ForceRate = 44100; Grade = 'B' }
    @{ Name = 'Focusrite';      Brand = 'Focusrite';         Mixer = 'Focusrite Control' }
    @{ Name = 'Scarlett';       Brand = 'Focusrite';         Mixer = 'Focusrite Control' }
    @{ Name = 'Clarett';        Brand = 'Focusrite';         Mixer = 'Focusrite Control' }
    @{ Name = 'Vocaster';       Brand = 'Focusrite';         Mixer = 'Focusrite Control' }
    @{ Name = 'Topping';        Brand = 'Topping';           Mixer = 'Topping 전용 앱'; Grade = 'B' }
    @{ Name = 'Lewitt';         Brand = 'Lewitt';            Mixer = 'CONTROL CENTER' }
    @{ Name = 'CONNECT 6';      Brand = 'Lewitt';            Mixer = 'CONTROL CENTER'; Grade = 'B' }
    @{ Name = 'CONNECT 2';      Brand = 'Lewitt';            Mixer = 'CONTROL CENTER'; Grade = 'C' }
    @{ Name = 'MOTU';           Brand = 'MOTU';              Mixer = 'MOTU 앱'; Grade = 'C' }
    @{ Name = 'Steinberg';      Brand = 'Steinberg';         Mixer = 'dspMixFx' }
    @{ Name = 'Yamaha';         Brand = 'Yamaha';            Mixer = 'Yamaha 유틸' }
    @{ Name = 'PreSonus';       Brand = 'PreSonus';          Mixer = 'UC Surface' }
    @{ Name = 'Behringer';      Brand = 'BEHRINGER';         Mixer = '제조사 유틸' }
    @{ Name = 'UMC';            Brand = 'BEHRINGER';         Mixer = '제조사 유틸' }
    @{ Name = 'Arturia';        Brand = 'Arturia';           Mixer = 'Arturia 소프트웨어 센터' }
    @{ Name = 'MiniFuse';       Brand = 'Arturia';           Mixer = 'Arturia 소프트웨어 센터' }
    @{ Name = 'Universal Audio';Brand = 'Universal Audio';   Mixer = 'UA Console'; Grade = 'C' }
    @{ Name = 'Apollo';         Brand = 'Universal Audio';   Mixer = 'UA Console'; Grade = 'C' }
    @{ Name = 'Apogee';         Brand = 'Apogee';            Mixer = '제조사 앱'; Grade = 'C' }
    @{ Name = 'Volt';           Brand = 'Universal Audio';   Mixer = 'UA Console'; Grade = 'C' }
    @{ Name = 'Antelope';       Brand = 'Antelope';          Mixer = 'Antelope Launcher' }
    @{ Name = 'SSL 2';          Brand = 'SSL';               Mixer = 'SSL 360'; Grade = 'C' }
    @{ Name = 'Solid State';    Brand = 'SSL';               Mixer = 'SSL 360' }
    @{ Name = 'SSL 2';          Brand = 'SSL';               Mixer = 'SSL 360' }
    @{ Name = 'Elgato';         Brand = 'Elgato';            Mixer = 'Wave Link' }
    @{ Name = 'Wave XLR';       Brand = 'Elgato';            Mixer = 'Wave Link' }
    @{ Name = 'GoXLR';          Brand = 'TC-Helicon';        Mixer = 'GoXLR App' }
    @{ Name = 'Komplete Audio'; Brand = 'Native Instruments';Mixer = 'NI 컨트롤 패널' }
    @{ Name = 'TASCAM';         Brand = 'TASCAM';            Mixer = 'TASCAM 설정 패널' }
    @{ Name = 'Zoom';           Brand = 'Zoom';              Mixer = 'Zoom 유틸' }
    @{ Name = 'Roland';         Brand = 'Roland';            Mixer = 'Roland 유틸' }
    @{ Name = 'Rubix';          Brand = 'Roland';            Mixer = 'Roland 유틸' }
    @{ Name = 'ICON';           Brand = 'ICON';              Mixer = '제조사 앱' }
    @{ Name = 'AG03';           Brand = 'Yamaha AG';         Mixer = 'AG 유틸'; Grade = 'C' }
    @{ Name = 'AG06';           Brand = 'Yamaha AG';         Mixer = 'AG 유틸'; Grade = 'C' }
    @{ Name = 'iD4';            Brand = 'Audient';           Mixer = 'iD 믹서 앱';  ForceRate = 44100; Grade = 'B' }
    @{ Name = 'iD14';          Brand = 'Audient';           Mixer = 'iD 믹서 앱';  ForceRate = 44100; Grade = 'B' }
    @{ Name = 'iD24';          Brand = 'Audient';           Mixer = 'iD 믹서 앱';  ForceRate = 44100; Grade = 'B' }
    @{ Name = 'iD44';          Brand = 'Audient';           Mixer = 'iD 믹서 앱';  ForceRate = 44100; Grade = 'B' }
    @{ Name = 'Sound Blaster';  Brand = 'Creative Sound Blaster'; Mixer = 'Creative App / Sound Blaster Command'; Card = $true }
    @{ Name = 'Creative';       Brand = 'Creative Sound Blaster'; Mixer = 'Creative App / Sound Blaster Command'; Card = $true }
    @{ Name = 'SB-Axx1';        Brand = 'Creative Sound Blaster'; Mixer = 'Creative App'; Card = $true }
    @{ Name = 'X-Fi';           Brand = 'Creative Sound Blaster'; Mixer = 'Creative App'; Card = $true }
    @{ Name = 'AE-5';           Brand = 'Creative Sound Blaster'; Mixer = 'Creative App'; Card = $true }
    @{ Name = 'AE-7';           Brand = 'Creative Sound Blaster'; Mixer = 'Creative App'; Card = $true }
    @{ Name = 'AE-9';           Brand = 'Creative Sound Blaster'; Mixer = 'Creative App'; Card = $true }
    @{ Name = 'GC7';            Brand = 'Creative Sound Blaster'; Mixer = 'Creative App'; Card = $true }
    @{ Name = 'Katana';         Brand = 'Creative Sound Blaster'; Mixer = 'Creative App'; Card = $true }
)
# 캡처보드 / 캡처카드 (투컴 방송PC 판별용)
$CaptureCardNames = @('Game Capture', 'Cam Link', 'HD60', '4K60', 'AVerMedia', 'Live Gamer', 'Ripsaw',
                      'Magewell', 'ATEM', 'USB Video', 'Capture Card', 'ShadowCast', 'Video Capture')
# 루프백성 캡처 엔드포인트 (사블의 What U Hear 등)
$LoopbackCaptureNames = @('What U Hear', 'What-U-Hear', '들리는 소리', 'Stereo Mix', '스테레오 믹스',
                          'Wave Out Mix', 'Mixed Output')
# 가상 / 온보드 / 모니터 판별용 키워드
$VirtualNames = @('VB-Audio', 'CABLE', 'Voicemeeter', 'SYNCROOM', 'NVIDIA Broadcast', 'Steam Streaming',
                  'OBS Virtual', 'Virtual Audio', 'Krisp', 'Discord Virtual', 'Vsound', 'ASIO Link')
$MonitorHints = @('VEN_10DE', 'VEN_8086', 'VEN_1002', 'NVIDIA High Definition', 'AMD High Definition',
                  'Intel(R) Display', 'Display Audio')
$OnboardHints = @('VEN_10EC', 'Realtek', 'High Definition Audio Device', 'VIA HD', 'Conexant', 'Cirrus')

# =====================================================================
# 1. Core Audio (MMDevice) 읽기용 인라인 C#
# =====================================================================
$CSharp = @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace YsAudio
{
    [StructLayout(LayoutKind.Sequential)]
    public struct PropertyKey
    {
        public Guid fmtid;
        public int pid;
    }

    [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
    public class MMDeviceEnumeratorComObject { }

    [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IMMDeviceEnumerator
    {
        [PreserveSig] int EnumAudioEndpoints(int dataFlow, int stateMask, out IMMDeviceCollection devices);
        [PreserveSig] int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice device);
        [PreserveSig] int GetDevice(string id, out IMMDevice device);
        [PreserveSig] int RegisterEndpointNotificationCallback(IntPtr client);
        [PreserveSig] int UnregisterEndpointNotificationCallback(IntPtr client);
    }

    [ComImport, Guid("0BD7A1BE-7A1A-44DB-8397-CC5392387B5E"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IMMDeviceCollection
    {
        [PreserveSig] int GetCount(out int count);
        [PreserveSig] int Item(int index, out IMMDevice device);
    }

    [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IMMDevice
    {
        [PreserveSig] int Activate(ref Guid iid, int clsCtx, IntPtr activationParams,
                                   [MarshalAs(UnmanagedType.IUnknown)] out object iface);
        [PreserveSig] int OpenPropertyStore(int stgmAccess, out IPropertyStore properties);
        [PreserveSig] int GetId([MarshalAs(UnmanagedType.LPWStr)] out string id);
        [PreserveSig] int GetState(out int state);
    }

    [ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IPropertyStore
    {
        [PreserveSig] int GetCount(out int props);
        [PreserveSig] int GetAt(int prop, out PropertyKey key);
        [PreserveSig] int GetValue(ref PropertyKey key, IntPtr pv);
        [PreserveSig] int SetValue(ref PropertyKey key, IntPtr pv);
        [PreserveSig] int Commit();
    }

    [ComImport, Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IAudioEndpointVolume
    {
        [PreserveSig] int RegisterControlChangeNotify(IntPtr notify);
        [PreserveSig] int UnregisterControlChangeNotify(IntPtr notify);
        [PreserveSig] int GetChannelCount(out int count);
        [PreserveSig] int SetMasterVolumeLevel(float level, ref Guid ctx);
        [PreserveSig] int SetMasterVolumeLevelScalar(float level, ref Guid ctx);
        [PreserveSig] int GetMasterVolumeLevel(out float level);
        [PreserveSig] int GetMasterVolumeLevelScalar(out float level);
        [PreserveSig] int SetChannelVolumeLevel(int ch, float level, ref Guid ctx);
        [PreserveSig] int SetChannelVolumeLevelScalar(int ch, float level, ref Guid ctx);
        [PreserveSig] int GetChannelVolumeLevel(int ch, out float level);
        [PreserveSig] int GetChannelVolumeLevelScalar(int ch, out float level);
        [PreserveSig] int SetMute([MarshalAs(UnmanagedType.Bool)] bool mute, ref Guid ctx);
        [PreserveSig] int GetMute([MarshalAs(UnmanagedType.Bool)] out bool mute);
    }

    public class EndpointInfo
    {
        public string Flow = "";
        public string Name = "";
        public string Desc = "";
        public string Iface = "";
        public string Full = "";
        public string Id = "";
        public int State = 0;
        public int SampleRate = 0;
        public int Channels = 0;
        public int Bits = 0;
        public bool IsDefault = false;
        public bool IsDefaultMultimedia = false;
        public bool IsDefaultComms = false;
        public int Muted = -1;      // -1 unknown, 0 no, 1 yes
        public float Volume = -1f;  // -1 unknown, else 0..1
        public string HardwareId = "";
        public string Error = "";
    }

    public static class Scanner
    {
        [DllImport("ole32.dll")]
        private static extern int PropVariantClear(IntPtr pvar);

        static Guid FMT_DEVICE = new Guid("a45c254e-df1c-4efd-8020-67d146a850e0");
        static Guid FMT_ENGINE = new Guid("f19f064d-082c-4e27-bc73-6882a1bb8e4c");
        static Guid FMT_IFACE  = new Guid("b3f8fa53-0004-438e-9003-51a46e139bfc");

        static IntPtr AllocPv()
        {
            IntPtr pv = Marshal.AllocCoTaskMem(64);
            for (int i = 0; i < 64; i++) Marshal.WriteByte(pv, i, 0);
            return pv;
        }

        static string GetStr(IPropertyStore ps, Guid fmt, int pid)
        {
            IntPtr pv = AllocPv();
            try
            {
                PropertyKey k = new PropertyKey();
                k.fmtid = fmt; k.pid = pid;
                if (ps.GetValue(ref k, pv) != 0) return "";
                string s = "";
                short vt = Marshal.ReadInt16(pv, 0);
                if (vt == 31)
                {
                    IntPtr p = Marshal.ReadIntPtr(pv, 8);
                    if (p != IntPtr.Zero) s = Marshal.PtrToStringUni(p);
                }
                PropVariantClear(pv);
                return s == null ? "" : s;
            }
            catch { return ""; }
            finally { Marshal.FreeCoTaskMem(pv); }
        }

        static byte[] GetBlob(IPropertyStore ps, Guid fmt, int pid)
        {
            IntPtr pv = AllocPv();
            try
            {
                PropertyKey k = new PropertyKey();
                k.fmtid = fmt; k.pid = pid;
                if (ps.GetValue(ref k, pv) != 0) return null;
                byte[] data = null;
                short vt = Marshal.ReadInt16(pv, 0);
                if (vt == 65)
                {
                    int cb = Marshal.ReadInt32(pv, 8);
                    IntPtr p = Marshal.ReadIntPtr(pv, IntPtr.Size == 8 ? 16 : 12);
                    if (p != IntPtr.Zero && cb > 0 && cb < 8192)
                    {
                        data = new byte[cb];
                        Marshal.Copy(p, data, 0, cb);
                    }
                }
                PropVariantClear(pv);
                return data;
            }
            catch { return null; }
            finally { Marshal.FreeCoTaskMem(pv); }
        }

        static string DefaultId(IMMDeviceEnumerator en, int flow, int role)
        {
            IMMDevice d;
            if (en.GetDefaultAudioEndpoint(flow, role, out d) != 0 || d == null) return "";
            string id;
            if (d.GetId(out id) != 0) return "";
            return id == null ? "" : id;
        }

        public static List<EndpointInfo> Scan()
        {
            List<EndpointInfo> list = new List<EndpointInfo>();
            IMMDeviceEnumerator en = (IMMDeviceEnumerator)(new MMDeviceEnumeratorComObject());

            string[] defIds = new string[6];
            for (int flow = 0; flow < 2; flow++)
                for (int role = 0; role < 3; role++)
                    defIds[flow * 3 + role] = DefaultId(en, flow, role);

            for (int flow = 0; flow < 2; flow++)
            {
                IMMDeviceCollection col;
                if (en.EnumAudioEndpoints(flow, 0x0F, out col) != 0 || col == null) continue;
                int n;
                if (col.GetCount(out n) != 0) continue;

                for (int i = 0; i < n; i++)
                {
                    EndpointInfo info = new EndpointInfo();
                    info.Flow = (flow == 0) ? "Render" : "Capture";
                    try
                    {
                        IMMDevice dev;
                        if (col.Item(i, out dev) != 0 || dev == null) continue;

                        string id;
                        dev.GetId(out id);
                        info.Id = id == null ? "" : id;

                        int st;
                        dev.GetState(out st);
                        info.State = st;

                        info.IsDefault            = (info.Id == defIds[flow * 3 + 0]);
                        info.IsDefaultMultimedia  = (info.Id == defIds[flow * 3 + 1]);
                        info.IsDefaultComms       = (info.Id == defIds[flow * 3 + 2]);

                        IPropertyStore ps;
                        if (dev.OpenPropertyStore(0, out ps) == 0 && ps != null)
                        {
                            info.Full  = GetStr(ps, FMT_DEVICE, 14);  // "엔드포인트 (기기)" 전체 이름
                            info.Name  = GetStr(ps, FMT_DEVICE, 2);   // 엔드포인트 이름 (리네임 대상)
                            info.Iface = GetStr(ps, FMT_IFACE, 6);    // 기기(드라이버) 이름
                            if (string.IsNullOrEmpty(info.Iface)) info.Iface = info.Full;
                            info.Desc  = info.Iface;
                            byte[] fmt = GetBlob(ps, FMT_ENGINE, 0);  // WAVEFORMATEX
                            if (fmt != null && fmt.Length >= 16)
                            {
                                info.Channels   = BitConverter.ToInt16(fmt, 2);
                                info.SampleRate = BitConverter.ToInt32(fmt, 4);
                                info.Bits       = BitConverter.ToInt16(fmt, 14);
                            }
                            Marshal.ReleaseComObject(ps);
                        }

                        if ((info.State & 1) == 1)
                        {
                            try
                            {
                                object o;
                                Guid iid = typeof(IAudioEndpointVolume).GUID;
                                if (dev.Activate(ref iid, 23, IntPtr.Zero, out o) == 0 && o != null)
                                {
                                    IAudioEndpointVolume vol = (IAudioEndpointVolume)o;
                                    bool m;
                                    if (vol.GetMute(out m) == 0) info.Muted = m ? 1 : 0;
                                    float v;
                                    if (vol.GetMasterVolumeLevelScalar(out v) == 0) info.Volume = v;
                                    Marshal.ReleaseComObject(o);
                                }
                            }
                            catch { }
                        }

                        Marshal.ReleaseComObject(dev);
                    }
                    catch (Exception ex)
                    {
                        info.Error = ex.Message;
                    }
                    list.Add(info);
                }
                Marshal.ReleaseComObject(col);
            }
            Marshal.ReleaseComObject(en);
            return list;
        }
    }
}
'@

# =====================================================================
# 2. 유틸리티
# =====================================================================
$script:Report = New-Object System.Collections.Generic.List[string]

function Write-Both {
    param([string]$Text = '', [string]$Color = 'Gray', [switch]$LogOnly)
    if (-not $LogOnly) { Write-Host $Text -ForegroundColor $Color }
    $script:Report.Add($Text) | Out-Null
}

function Get-StateName {
    param([int]$State)
    switch ($State -band 0x0F) {
        1 { '활성' }
        2 { '사용 안 함(비활성)' }
        4 { '연결 안 됨' }
        8 { '플러그 빠짐' }
        default { "알 수 없음($State)" }
    }
}

function Test-AnyMatch {
    param([string]$Text, [string[]]$Patterns)
    if ([string]::IsNullOrEmpty($Text)) { return $false }
    foreach ($p in $Patterns) {
        if ($Text -like "*$p*") { return $true }
    }
    return $false
}

function Get-VolPct {
    <# 실시간 스캔은 0~1 스칼라, 리포트 파일은 이미 % 단위. 항상 %로 맞춘다. #>
    param($Endpoint)
    if ($null -eq $Endpoint -or $Endpoint.Volume -lt 0) { return -1 }
    if ($script:IsDumpMode) { return [int][math]::Round([double]$Endpoint.Volume) }
    return [int][math]::Round([double]$Endpoint.Volume * 100)
}

function New-Finding {
    param([string]$Level, [string]$Title, [string]$Detail = '', [string]$Fix = '')
    [pscustomobject]@{ Level = $Level; Title = $Title; Detail = $Detail; Fix = $Fix }
}

# =====================================================================
# 3. 장치 수집
# =====================================================================
function Get-EndpointsFromSystem {
    if (-not ('YsAudio.Scanner' -as [type])) {
        Add-Type -TypeDefinition $CSharp -ErrorAction Stop | Out-Null
    }
    $raw = [YsAudio.Scanner]::Scan()

    # 부모 하드웨어 ID(USB\VID_xxxx&PID_xxxx 등) 붙이기 - 실패해도 무시
    $canPnp = $null -ne (Get-Command Get-PnpDeviceProperty -ErrorAction SilentlyContinue)
    foreach ($e in $raw) {
        if ($canPnp -and $e.Id) {
            try {
                $inst = 'SWD\MMDEVAPI\' + $e.Id
                $p = Get-PnpDeviceProperty -InstanceId $inst -KeyName 'DEVPKEY_Device_Parent' -ErrorAction Stop
                if ($p -and $p.Data) { $e.HardwareId = [string]$p.Data }
            } catch { }
        }
    }
    return $raw
}

function Get-EndpointsFromDump {
    param([string]$Path)
    # 진단 결과 파일(routing-check_*.txt)을 그대로 넣은 경우 그쪽 파서를 쓴다
    $head = (Get-Content -LiteralPath $Path -Encoding UTF8 -TotalCount 40) -join "`n"
    if ($head -match '윤슬 라우팅 진단 결과') {
        return (Get-ReportSnapshot -Path $Path).Endpoints
    }
    $flow = 'Render'
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($line in (Get-Content -LiteralPath $Path -Encoding UTF8)) {
        if ($line -match '^===\s*Render') { $flow = 'Render'; continue }
        if ($line -match '^===\s*Capture') { $flow = 'Capture'; continue }
        if ($line.Trim() -eq '') { continue }
        $parts = $line -split '\|'
        if ($parts.Count -lt 6) { continue }
        $rate = 0; $ch = 0
        if ($parts[2] -match '(\d+)Hz') { $rate = [int]$Matches[1] }
        if ($parts[2] -match '(\d+)ch') { $ch = [int]$Matches[1] }
        $st = 0
        if ($parts[3] -match 'st=(\d+)') { $st = [int]$Matches[1] }
        $o = New-Object psobject -Property @{
            Flow = $flow; Name = $parts[0].Trim(); Desc = $parts[1].Trim(); Iface = $parts[1].Trim()
            Id = $parts[5].Trim(); State = ($st -band 0x0F); SampleRate = $rate; Channels = $ch; Bits = 0
            IsDefault = $false; IsDefaultMultimedia = $false; IsDefaultComms = $false
            Muted = -1; Volume = -1.0; HardwareId = $parts[4].Trim(); Error = ''
        }
        $list.Add($o) | Out-Null
    }
    return $list
}

function Get-ReportSnapshot {
    <# 예전 진단 결과 파일(routing-check_*.txt)에서 엔드포인트 목록과 요약을 읽어온다 #>
    param([string]$Path)
    $snap = [pscustomobject]@{
        Endpoints = New-Object System.Collections.Generic.List[object]
        Meta      = @{}
        Problems  = New-Object System.Collections.Generic.List[string]
        Warns     = New-Object System.Collections.Generic.List[string]
    }
    $inDump = $false
    $flow = 'Render'
    foreach ($l in (Get-Content -LiteralPath $Path -Encoding UTF8)) {
        if ($l -match '전체 엔드포인트 덤프') { $inDump = $true; continue }
        if ($l -match '^===\s*/?YS-DATA')     { $inDump = $false; continue }
        if ($l -match '^===\s*Render')  { $flow = 'Render';  continue }
        if ($l -match '^===\s*Capture') { $flow = 'Capture'; continue }

        if ($l -match '^(setup|pc|time|version|defaultRender|defaultCapture)=(.*)$') {
            $snap.Meta[$Matches[1]] = $Matches[2].Trim(); continue
        }
        if ($l -match '^problem=(.*)$') { $snap.Problems.Add($Matches[1].Trim()) | Out-Null; continue }
        if ($l -match '^warn=(.*)$')    { $snap.Warns.Add($Matches[1].Trim())    | Out-Null; continue }

        if (-not $inDump) { continue }
        $p = $l -split '\|'
        if ($p.Count -lt 8) { continue }
        if ($p[7] -notmatch '^\{') { continue }
        $rate = 0; $ch = 0; $st = 0; $mute = -1; $vol = -1
        if ($p[2] -match '(\d+)Hz') { $rate = [int]$Matches[1] }
        if ($p[2] -match '(\d+)ch') { $ch   = [int]$Matches[1] }
        if ($p[3] -match 'st=(\d+)')   { $st   = [int]$Matches[1] }
        if ($p[4] -match 'mute=(-?\d+)') { $mute = [int]$Matches[1] }
        if ($p[5] -match 'vol=(\d+)')    { $vol  = [int]$Matches[1] }
        $snap.Endpoints.Add([pscustomobject]@{
            Flow = $flow; Name = $p[0].Trim(); Desc = $p[1].Trim(); Iface = $p[1].Trim()
            SampleRate = $rate; Channels = $ch; State = $st; Bits = 0
            Muted = $mute; Volume = $vol; HardwareId = $p[6].Trim(); Id = $p[7].Trim()
            IsDefault = $false; IsDefaultMultimedia = $false; IsDefaultComms = $false; Error = ''
        }) | Out-Null
    }
    foreach ($key in @('defaultRender','defaultCapture')) {
        $v = $snap.Meta[$key]
        if (-not $v) { continue }
        $parts = $v -split '\|'
        $flowWant = if ($key -eq 'defaultRender') { 'Render' } else { 'Capture' }
        foreach ($e in $snap.Endpoints) {
            if ($e.Flow -eq $flowWant -and $e.Name -eq $parts[0] -and ($e.State -band 1) -eq 1) {
                $e.IsDefault = $true; break
            }
        }
    }
    return $snap
}

function Show-Diff {
    <# 기준선과 지금 상태를 비교해 무엇이 바뀌었는지 출력 #>
    param($Base, $Endpoints)

    Write-Both "---------------------------------------------------------------------" 'DarkGray'
    Write-Both " 기준선과 비교" 'Magenta'
    Write-Both "---------------------------------------------------------------------" 'DarkGray'
    Write-Both ("  기준선 : {0} / {1}" -f $Base.Meta['pc'], $Base.Meta['time']) 'DarkGray'
    Write-Both ("  현재   : {0} / {1}" -f $env:COMPUTERNAME, $startedAt.ToString('yyyy-MM-dd HH:mm:ss')) 'DarkGray'
    Write-Both ''

    $baseById = @{}
    foreach ($e in $Base.Endpoints) { $baseById[$e.Id] = $e }
    $curById = @{}
    foreach ($e in $Endpoints) { $curById[$e.Id] = $e }

    $changes = New-Object System.Collections.Generic.List[string]
    $isAct = { param($x) ($x.State -band 1) -eq 1 }

    foreach ($e in $Endpoints) {
        $b = $baseById[$e.Id]
        if ($null -eq $b) {
            if (& $isAct $e) { $changes.Add("[추가] $($e.Flow) / $($e.Name) ($($e.Desc)) - 기준선에 없던 장치") | Out-Null }
            continue
        }
        if ($b.Name -ne $e.Name) {
            $changes.Add("[이름] $($e.Flow) / $($e.Desc) : '$($b.Name)' -> '$($e.Name)'") | Out-Null
        }
        if ($b.SampleRate -ne $e.SampleRate -and $e.SampleRate -gt 0 -and $b.SampleRate -gt 0) {
            $changes.Add("[샘플레이트] $($e.Flow) / $($e.Name) : $($b.SampleRate)Hz -> $($e.SampleRate)Hz") | Out-Null
        }
        if (($b.State -band 0x0F) -ne ($e.State -band 0x0F)) {
            $changes.Add("[상태] $($e.Flow) / $($e.Name) : $(Get-StateName $b.State) -> $(Get-StateName $e.State)") | Out-Null
        }
        if ($b.Muted -eq 0 -and $e.Muted -eq 1) {
            $changes.Add("[음소거] $($e.Flow) / $($e.Name) : 음소거됨") | Out-Null
        }
        $bp = if ($b.Volume -lt 0) { -1 } else { [int][math]::Round([double]$b.Volume) }
        $ep = Get-VolPct $e
        if ($bp -ge 0 -and $ep -ge 0 -and [math]::Abs($bp - $ep) -ge 15) {
            $changes.Add("[볼륨] $($e.Flow) / $($e.Name) : $bp% -> $ep%") | Out-Null
        }
    }
    foreach ($b in $Base.Endpoints) {
        if (-not (& $isAct $b)) { continue }
        $c = $curById[$b.Id]
        if ($null -eq $c) {
            $changes.Add("[사라짐] $($b.Flow) / $($b.Name) ($($b.Desc)) - 기준선에는 있었으나 지금은 없음") | Out-Null
        }
    }

    $defR = $Endpoints | Where-Object { $_.Flow -eq 'Render'  -and $_.IsDefault } | Select-Object -First 1
    $defC = $Endpoints | Where-Object { $_.Flow -eq 'Capture' -and $_.IsDefault } | Select-Object -First 1
    $bR = $Base.Meta['defaultRender']; $bC = $Base.Meta['defaultCapture']
    if ($defR -and $bR) {
        $now = "$($defR.Name)|$($defR.Desc)"
        if ($now -ne $bR) { $changes.Add("[기본 재생] '$bR' -> '$now'") | Out-Null }
    }
    if ($defC -and $bC) {
        $now = "$($defC.Name)|$($defC.Desc)"
        if ($now -ne $bC) { $changes.Add("[기본 녹음] '$bC' -> '$now'") | Out-Null }
    }

    if ($changes.Count -eq 0) {
        Write-Both "  기준선과 달라진 것이 없습니다." 'Green'
    }
    else {
        Write-Both "  달라진 것 $($changes.Count)건" 'Magenta'
        foreach ($c in $changes) {
            $col = if ($c -like '[[]사라짐*' -or $c -like '[[]음소거*') { 'Red' }
                   elseif ($c -like '[[]이름*' -or $c -like '[[]기본*') { 'Yellow' } else { 'Gray' }
            Write-Both ("    " + $c) $col
        }
    }
    Write-Both ''
}

function ConvertTo-AppKey {
    <# \Device\HarddiskVolume3\Program Files\... 와 C:\Program Files\... 를 같은 값으로 맞춘다 #>
    param([string]$Path)
    if (-not $Path) { return '' }
    $s = $Path
    $s = $s -replace '^\\\\\?\\', ''
    $s = $s -replace '^\\Device\\HarddiskVolume\d+', ''
    $s = $s -replace '^[A-Za-z]:', ''
    return $s.ToLower()
}

function Get-AppAssignments {
    <#
      앱별 오디오 장치 지정을 읽는다. 저장소가 두 군데다.
        A. HKCU\Software\Microsoft\Multimedia\Audio\DefaultEndpoint  (현재 볼륨 믹서가 쓰는 곳)
        B. HKCU\...\Internet Explorer\LowRegistry\Audio\PolicyConfig\PropertyStore  (예전 기록이 쌓이는 곳)
      레지스트리를 읽기만 한다.
    #>
    $list = New-Object System.Collections.Generic.List[object]

    # ---- A. 현재 저장소 ----
    $rootA = 'HKCU:\Software\Microsoft\Multimedia\Audio\DefaultEndpoint'
    if (Test-Path $rootA) {
        foreach ($k in (Get-ChildItem -Path $rootA -ErrorAction SilentlyContinue)) {
            $item = Get-Item -Path $k.PSPath -ErrorAction SilentlyContinue
            if (-not $item) { continue }
            $appPath = [string]$item.GetValue('')
            if (-not $appPath) { continue }
            foreach ($vn in @('000_000', '001_000')) {
                $raw = [string]$item.GetValue($vn)
                if (-not $raw) { continue }
                if ($raw -notmatch '(\{0\.0\.(\d)\.00000000\}\.\{[0-9a-fA-F-]+\})') { continue }
                $list.Add([pscustomobject]@{
                    Store      = 'A'
                    App        = ($appPath -split '\\')[-1]
                    AppPath    = $appPath
                    AppKey     = (ConvertTo-AppKey $appPath)
                    Role       = $(if ($vn -eq '000_000') { '일반' } else { '통신' })
                    Flow       = $(if ($Matches[2] -eq '0') { 'Render' } else { 'Capture' })
                    EndpointId = $Matches[1]
                    Device     = ''
                }) | Out-Null
            }
        }
    }

    # ---- B. 예전 저장소 ----
    $rootB = 'HKCU:\Software\Microsoft\Internet Explorer\LowRegistry\Audio\PolicyConfig\PropertyStore'
    if (Test-Path $rootB) {
        foreach ($k in (Get-ChildItem -Path $rootB -ErrorAction SilentlyContinue)) {
            $item = Get-Item -Path $k.PSPath -ErrorAction SilentlyContinue
            if (-not $item) { continue }
            $raw = [string]$item.GetValue('')
            if (-not $raw -or $raw -notlike '*|*') { continue }
            $parts = $raw -split '\|', 2
            $dev = $parts[0]
            $app = ($parts[1] -split '%b')[0]
            if (-not $app -or $app -eq '#') { continue }
            $vid = ''
            if ($dev -match '(vid_[0-9a-fA-F]{4})') { $vid = $Matches[1].ToUpper() }
            elseif ($dev -match '(ven_[0-9a-fA-F]{4})') { $vid = $Matches[1].ToUpper() }
            $list.Add([pscustomobject]@{
                Store      = 'B'
                App        = ($app -split '\\')[-1]
                AppPath    = $app
                AppKey     = (ConvertTo-AppKey $app)
                Role       = '-'
                Flow       = $(if ($dev -match 'pcm_in|_in_|capture') { 'Capture' } else { 'Render' })
                EndpointId = ''
                Device     = $vid
            }) | Out-Null
        }
    }
    return $list
}

# =====================================================================
# 4. 기기 분류 / 그룹핑
# =====================================================================
function Get-DeviceGroups {
    param($Endpoints)

    $groups = @{}
    foreach ($e in $Endpoints) {
        # 기기 단위 묶음은 '기기 이름' 기준. 엔드포인트 이름은 고객이 바꾸므로 절대 쓰지 않는다.
        $label = if ($e.Iface) { $e.Iface } elseif ($e.Desc) { $e.Desc } else { '알 수 없는 기기' }
        $key = $label.Trim().ToUpper()

        if (-not $groups.ContainsKey($key)) {
            $groups[$key] = [pscustomobject]@{
                Key       = $key
                Label     = $label.Trim()
                Hardware  = ''
                Brand     = ''
                Mixer     = ''
                Kind      = ''
                ForceRate = 0
                Grade     = ''
                Endpoints = New-Object System.Collections.Generic.List[object]
            }
        }
        # 연결이 끊긴 엔드포인트는 하드웨어ID가 비므로, 채워진 값이 나오면 그때 기록
        if (-not $groups[$key].Hardware -and $e.HardwareId) { $groups[$key].Hardware = $e.HardwareId }
        $groups[$key].Endpoints.Add($e) | Out-Null
    }

    foreach ($g in $groups.Values) {
        # 판정 근거는 기기 이름과 하드웨어ID뿐. 엔드포인트 이름(Chrome/Discord/Syncroom 등)은 쓰지 않는다.
        $probe = ($g.Hardware + ' ' + $g.Label)
        $hit = $null
        if (-not (Test-AnyMatch $probe $VirtualNames) -and -not (Test-AnyMatch $probe $CaptureCardNames)) {
            foreach ($v in $VendorById)   { if ($probe -match [regex]::Escape($v.Id)) { $hit = $v; break } }
            if (-not $hit) {
                foreach ($v in $VendorByName) {
                    if ($probe -like "*$($v.Name)*") { $hit = $v; break }
                }
            }
        }
        if ($hit) {
            $g.Brand = $hit.Brand
            $g.Mixer = $hit.Mixer
            $g.Kind  = if ($hit.ContainsKey('Card')) { '게임 사운드카드' } else { '오디오 인터페이스' }
            if ($hit.ContainsKey('ForceRate')) { $g.ForceRate = [int]$hit.ForceRate }
            if ($hit.ContainsKey('Grade'))     { $g.Grade = [string]$hit.Grade }
        }
        elseif (Test-AnyMatch $probe $CaptureCardNames) { $g.Kind = '캡처보드'; $g.Brand = '캡처 장치' }
        elseif (Test-AnyMatch $probe $VirtualNames) { $g.Kind = '가상 장치';  $g.Brand = '가상/소프트웨어' }
        elseif (Test-AnyMatch $probe $MonitorHints) { $g.Kind = '모니터/HDMI'; $g.Brand = '그래픽 출력' }
        elseif (Test-AnyMatch $probe $OnboardHints) { $g.Kind = '메인보드 내장'; $g.Brand = '온보드' }
        else { $g.Kind = '기타' }
    }

    return @($groups.Values)
}

# =====================================================================
# 5. 진단 규칙
# =====================================================================
function Get-SetupMode {
    param($Groups)
    $act = { param($g) @($g.Endpoints | Where-Object { ($_.State -band 1) -eq 1 }).Count -gt 0 }
    $hasCapCard = @($Groups | Where-Object { $_.Kind -eq '캡처보드' -and (& $act $_) }).Count -gt 0
    if ($hasCapCard) { return 'Stream' }
    return 'Single'
}

function Invoke-Diagnosis {
    param($Endpoints, $Groups, [string]$Setup = 'Single')

    $f = New-Object System.Collections.Generic.List[object]
    $lvlNoDefault = if ($script:IsDumpMode) { '정보' } else { '주의' }
    $isGame   = ($Setup -eq 'Game')
    $isStream = ($Setup -eq 'Stream')
    $active = @($Endpoints | Where-Object { ($_.State -band 1) -eq 1 })
    $ifaces = @($Groups | Where-Object { $_.Kind -eq '오디오 인터페이스' -or $_.Kind -eq '게임 사운드카드' })
    $capCards = @($Groups | Where-Object { $_.Kind -eq '캡처보드' -and @($_.Endpoints | Where-Object { ($_.State -band 1) -eq 1 }).Count -gt 0 })
    $ifaceActive = @($ifaces | Where-Object { @($_.Endpoints | Where-Object { ($_.State -band 1) -eq 1 }).Count -gt 0 })

    # --- 1) 오디오 인터페이스 감지 -------------------------------------
    if ($ifaceActive.Count -eq 0) {
        $f.Add((New-Finding '문제' '오디오 인터페이스가 감지되지 않음' `
            '연결된 오인페·사운드카드를 찾지 못했습니다. USB가 빠졌거나 드라이버가 죽은 상태입니다.' `
            'USB 케이블을 다시 꽂고(가능하면 뒷면 USB 포트 직결, 허브 X) 전원을 확인한 뒤 다시 진단해 주세요. 투컴이라면 오인페가 붙어 있는 PC에서 실행해 주세요.')) | Out-Null
    }
    else {
        $names = ($ifaceActive | ForEach-Object { "$($_.Label) [$($_.Brand)]" }) -join ', '
        $f.Add((New-Finding '정상' '오디오 인터페이스 감지됨' $names '')) | Out-Null
        if ($ifaceActive.Count -gt 1) {
            $f.Add((New-Finding '주의' '오디오 인터페이스가 2대 이상 연결됨' `
                $names `
                '두 대가 동시에 붙어 있으면 윈도우가 엉뚱한 쪽을 기본 장치로 잡습니다. 지금 쓰는 것만 남기고 나머지는 USB를 빼주세요.')) | Out-Null
        }
    }

    $ifaceEpIds = @{}
    foreach ($g in $ifaceActive) { foreach ($e in $g.Endpoints) { $ifaceEpIds[$e.Id] = $g } }

    # --- 2) 기본 재생 장치 ---------------------------------------------
    $defRender = $Endpoints | Where-Object { $_.Flow -eq 'Render' -and $_.IsDefault } | Select-Object -First 1
    $defComms  = $Endpoints | Where-Object { $_.Flow -eq 'Render' -and $_.IsDefaultComms } | Select-Object -First 1
    $defCap    = $Endpoints | Where-Object { $_.Flow -eq 'Capture' -and $_.IsDefault } | Select-Object -First 1
    $defCapCom = $Endpoints | Where-Object { $_.Flow -eq 'Capture' -and $_.IsDefaultComms } | Select-Object -First 1

    if ($null -eq $defRender) {
        $f.Add((New-Finding $lvlNoDefault '기본 재생 장치를 확인하지 못함' '' '소리 설정에서 출력 장치를 확인해 주세요.')) | Out-Null
    }
    elseif ($ifaceEpIds.ContainsKey($defRender.Id)) {
        $f.Add((New-Finding '정상' '기본 재생 장치가 오인페로 잡혀 있음' "$($defRender.Name) ($($ifaceEpIds[$defRender.Id].Label))" '')) | Out-Null
    }
    else {
        $owner = ($Groups | Where-Object { $_.Endpoints.Id -contains $defRender.Id } | Select-Object -First 1)
        # 이미 표준대로 채널이 나뉘어 있는 PC인지 확인 - 그렇다면 모니터링을 잠시 돌려둔 것일 수 있다
        $named = 0
        foreach ($g in $ifaceActive) {
            foreach ($e in $g.Endpoints) {
                if ($e.Flow -ne 'Render' -or ($e.State -band 1) -ne 1) { continue }
                foreach ($n in ($YS.RequiredRenderNames + $YS.OptionalRenderNames)) {
                    if ($e.Name -and $e.Name.Trim().ToUpper() -eq $n.ToUpper()) { $named++; break }
                }
            }
        }
        if ($named -ge 2) {
            $f.Add((New-Finding '주의' '기본 재생 장치가 오인페가 아님 (일시적으로 돌려둔 상태일 수 있음)' `
                "지금 기본 출력: $($defRender.Name) / $($defRender.Desc) [$($owner.Kind)]" `
                '오인페 채널은 표준대로 나뉘어 있습니다. 스피커로 잠깐 듣는 중이라면 정상입니다. 다만 앱별 출력이 지정되지 않은 소리는 전부 이쪽으로 나가니, 방송 전에는 오인페로 되돌리는 게 안전합니다.')) | Out-Null
        }
        else {
            $f.Add((New-Finding '문제' '기본 재생 장치가 오인페가 아님' `
                "지금 기본 출력: $($defRender.Name) / $($defRender.Desc) [$($owner.Kind)]" `
                '소리 설정 > 출력에서 오인페 출력을 기본 장치로 바꿔주세요. (모니터 HDMI나 메인보드 내장으로 잡혀 있으면 스피커에서 소리가 안 납니다.)')) | Out-Null
        }
    }

    if ($defComms -and $defRender -and $defComms.Id -ne $defRender.Id) {
        $f.Add((New-Finding '정보' '기본 장치와 통신용 기본 장치가 서로 다름' `
            "일반: $($defRender.Name) / 통신용: $($defComms.Name)" `
            '의도한 게 아니라면 소리 제어판(mmsys.cpl)에서 통신용 기본 장치도 같은 걸로 맞춰주세요.')) | Out-Null
    }

    # --- 3) 기본 녹음 장치 ---------------------------------------------
    if ($null -eq $defCap) {
        $f.Add((New-Finding $lvlNoDefault '기본 녹음 장치를 확인하지 못함' '' '소리 설정에서 입력 장치를 확인해 주세요.')) | Out-Null
    }
    elseif ($ifaceEpIds.ContainsKey($defCap.Id)) {
        $f.Add((New-Finding '정상' '기본 녹음 장치가 오인페로 잡혀 있음' "$($defCap.Name) ($($ifaceEpIds[$defCap.Id].Label))" '')) | Out-Null
    }
    else {
        $micCapable = @($ifaceActive | Where-Object {
            @($_.Endpoints | Where-Object { $_.Flow -eq 'Capture' -and ($_.State -band 1) -eq 1 }).Count -gt 0
        })
        if ($isGame -or $micCapable.Count -eq 0) {
            $f.Add((New-Finding '정보' '기본 녹음 장치가 오인페가 아님 (이 PC에는 마이크 계통이 없음)' `
                "지금 기본 입력: $($defCap.Name) / $($defCap.Desc)" `
                '투컴에서 마이크가 방송PC에만 있다면 정상입니다. 이 PC에 마이크를 물릴 거라면 오인페 입력을 기본 장치로 바꿔주세요.')) | Out-Null
        }
        else {
            $f.Add((New-Finding '문제' '기본 녹음 장치가 오인페가 아님' `
                "지금 기본 입력: $($defCap.Name) / $($defCap.Desc)" `
                '소리 설정 > 입력에서 오인페 입력을 기본 장치로 바꿔주세요. 마이크가 안 잡히는 대부분의 원인입니다.')) | Out-Null
        }
    }
    if ($defCapCom -and $defCap -and $defCapCom.Id -ne $defCap.Id) {
        $f.Add((New-Finding '정보' '녹음 쪽 기본/통신용 장치가 서로 다름' `
            "일반: $($defCap.Name) / 통신용: $($defCapCom.Name)" '')) | Out-Null
    }

    # --- 4) 샘플레이트 ---------------------------------------------------
    foreach ($g in $ifaceActive) {
        $rates = @($g.Endpoints | Where-Object { ($_.State -band 1) -eq 1 -and $_.SampleRate -gt 0 } |
                   ForEach-Object { $_.SampleRate } | Sort-Object -Unique)
        if ($rates.Count -eq 0) { continue }

        if ($g.ForceRate -gt 0) {
            $bad = @($rates | Where-Object { $_ -ne $g.ForceRate })
            if ($bad.Count -gt 0) {
                $wrong = @($g.Endpoints | Where-Object { ($_.State -band 1) -eq 1 -and $_.SampleRate -gt 0 -and $_.SampleRate -ne $g.ForceRate } |
                           ForEach-Object { "$($_.Flow) / $($_.Name) = $($_.SampleRate)Hz" })
                $f.Add((New-Finding '문제' "$($g.Label): 샘플레이트가 $($g.ForceRate)Hz가 아님" `
                    ($wrong -join "`r`n") `
                    "$($g.Brand) 계열은 $($g.ForceRate)Hz가 아니면 출력이 통째로 무음이 되는 사례가 있습니다. 소리 제어판(mmsys.cpl) > 각 장치 속성 > 고급에서 전부 $($g.ForceRate)Hz(2채널)로 통일해 주세요.")) | Out-Null
            }
            else {
                $f.Add((New-Finding '정상' "$($g.Label): 샘플레이트 $($g.ForceRate)Hz로 통일됨" '' '')) | Out-Null
            }
        }
        elseif ($rates.Count -gt 1) {
            $detail = @($g.Endpoints | Where-Object { ($_.State -band 1) -eq 1 -and $_.SampleRate -gt 0 } |
                        ForEach-Object { "$($_.Flow) / $($_.Name) = $($_.SampleRate)Hz" })
            $f.Add((New-Finding '주의' "$($g.Label): 엔드포인트마다 샘플레이트가 다름 ($($rates -join ', ')Hz)" `
                ($detail -join "`r`n") `
                '드라이버 클럭과 다른 값이 섞이면 리샘플링이 끼거나 특정 앱만 무음이 됩니다. 소리 제어판 > 고급에서 전부 같은 값(보통 48000Hz, Audient은 44100Hz)으로 맞춰주세요.')) | Out-Null
        }
        else {
            $f.Add((New-Finding '정상' "$($g.Label): 샘플레이트 $($rates[0])Hz로 통일됨" '' '')) | Out-Null
        }
    }

    # --- 5) 윤슬 표준 리네임 ---------------------------------------------
    foreach ($g in $ifaceActive) {
        $needR = $YS.RequiredRenderNames
        $needC = $YS.RequiredCaptureNames
        if ($isGame)   { $needC = @() }   # 게임PC에는 마이크 계통이 없다

        $haveR = @($g.Endpoints | Where-Object { $_.Flow -eq 'Render'  -and ($_.State -band 1) -eq 1 } | ForEach-Object { $_.Name })
        $haveC = @($g.Endpoints | Where-Object { $_.Flow -eq 'Capture' -and ($_.State -band 1) -eq 1 } | ForEach-Object { $_.Name })

        $missR = @(); $missC = @()
        foreach ($n in $needR) {
            $hit = $false
            foreach ($x in $haveR) { if ($x -and $x.Trim().ToUpper() -eq $n.ToUpper()) { $hit = $true; break } }
            if (-not $hit) { $missR += $n }
        }
        foreach ($n in $needC) {
            $hit = $false
            foreach ($x in $haveC) { if ($x -and $x.Trim().ToUpper() -eq $n.ToUpper()) { $hit = $true; break } }
            if (-not $hit) { $missC += $n }
        }

        $detail = "재생: " + (($haveR | Sort-Object) -join ', ') + "`r`n녹음: " + (($haveC | Sort-Object) -join ', ')
        $missAll = @($missR + $missC)
        $needAll = @($needR + $needC)

        if ($haveR.Count -eq 0 -and $haveC.Count -eq 0) {
            $f.Add((New-Finding '주의' "$($g.Label): 활성 엔드포인트가 없음" '' `
                '장치가 전부 사용 안 함으로 꺼져 있을 수 있습니다. 소리 제어판에서 사용으로 바꿔주세요.')) | Out-Null
        }
        elseif ($missAll.Count -eq 0) {
            $f.Add((New-Finding '정상' "$($g.Label): 윤슬 표준 이름 적용됨" $detail '')) | Out-Null
        }
        elseif ($missAll.Count -ge $needAll.Count) {
            $f.Add((New-Finding '주의' "$($g.Label): 표준 이름이 적용되지 않음" $detail `
                '이 PC에는 LoopbackKit 이름 변경이 아직 안 들어갔습니다. 세팅 전이면 정상이고, 세팅 후라면 이름이 초기화된 것이니 알려주세요.')) | Out-Null
        }
        else {
            $miss = @()
            if ($missR.Count) { $miss += ('재생 ' + ($missR -join ', ')) }
            if ($missC.Count) { $miss += ('녹음 ' + ($missC -join ', ')) }
            $f.Add((New-Finding '주의' "$($g.Label): 표준 이름이 일부만 있음 (없는 것: $($miss -join ' / '))" $detail `
                '드라이버 재설치나 윈도우 업데이트로 일부 엔드포인트 이름이 되돌아갔을 수 있습니다. 해당 채널 라우팅도 같이 확인이 필요합니다.')) | Out-Null
        }
    }

    # --- 6) 음소거 / 볼륨 -------------------------------------------------
    $volTargets = @($active | Where-Object { $_.Flow -eq 'Render' -and ($_.IsDefault -or $ifaceEpIds.ContainsKey($_.Id)) })
    foreach ($e in $volTargets) {
        if ($e.Muted -eq 1) {
            $f.Add((New-Finding '문제' "음소거 상태: $($e.Name)" `
                "$($e.Desc) / 재생" `
                '볼륨 믹서에서 이 장치의 음소거를 해제해 주세요.')) | Out-Null
        }
        elseif ((Get-VolPct $e) -ge 0 -and (Get-VolPct $e) -lt ($YS.LowVolumeThreshold * 100)) {
            $pct = Get-VolPct $e
            $f.Add((New-Finding '주의' "볼륨이 매우 낮음: $($e.Name) ($pct%)" `
                "$($e.Desc) / 재생" `
                '윈도우 볼륨을 올려주세요. (윤슬 표준에서는 윈도우 쪽 볼륨은 100%로 두고 오인페 노브로 조절합니다.)')) | Out-Null
        }
    }

    # --- 7) 유령 / 잔재 장치 ----------------------------------------------
    $deadIfaces = @($ifaces | Where-Object { @($_.Endpoints | Where-Object { ($_.State -band 1) -eq 1 }).Count -eq 0 })
    if ($deadIfaces.Count -gt 0) {
        $detail = @($deadIfaces | ForEach-Object {
            "$($_.Label) - 엔드포인트 $($_.Endpoints.Count)개가 전부 " + (Get-StateName ($_.Endpoints[0].State))
        })
        $f.Add((New-Finding '주의' "지금 연결되어 있지 않은 오인페 흔적 $($deadIfaces.Count)대" `
            ($detail -join "`r`n") `
            '예전에 쓰던 오인페 기록입니다. 이름이 겹치면 앱이 엉뚱한 쪽을 잡을 수 있으니, 다시 쓸 게 아니면 장치 관리자에서 정리하는 게 좋습니다.')) | Out-Null
    }

    foreach ($g in $ifaceActive) {
        $off = @($g.Endpoints | Where-Object { ($_.State -band 1) -ne 1 })
        if ($off.Count -gt 0) {
            $detail = @($off | Select-Object -First 10 | ForEach-Object { "$($_.Flow) / $($_.Name) - $(Get-StateName $_.State)" })
            if ($off.Count -gt 10) { $detail += "... 외 $($off.Count - 10)개" }
            $f.Add((New-Finding '정보' "$($g.Label): 지금 꺼져 있는 채널 $($off.Count)개" ($detail -join "`r`n") `
                '안 쓰는 채널이면 그대로 두셔도 됩니다. 쓰려던 채널이 여기 있으면 알려주세요.')) | Out-Null
        }
    }

    $orphanStd = @($Endpoints | Where-Object {
        ($_.State -band 1) -ne 1 -and -not $ifaceEpIds.ContainsKey($_.Id) -and
        -not (Test-AnyMatch (($_.Desc + ' ' + $_.HardwareId)) $MonitorHints)
    } | Where-Object {
        $n = $_.Name; $hit = $false
        foreach ($std in ($YS.RequiredRenderNames + $YS.RequiredCaptureNames + @('PC', 'Syncroom'))) {
            if ($n -and $n.Trim().ToUpper() -eq $std.ToUpper()) { $hit = $true; break }
        }
        $hit
    })
    if ($orphanStd.Count -gt 0) {
        $detail = @($orphanStd | Select-Object -First 10 | ForEach-Object { "$($_.Flow) / $($_.Name) / $($_.Desc) - $(Get-StateName $_.State)" })
        $f.Add((New-Finding '주의' "표준 이름을 쓰는 비활성 장치 $($orphanStd.Count)개" ($detail -join "`r`n") `
            '지금 쓰는 오인페가 아닌 장치에 표준 이름이 남아 있습니다. 앱이 이쪽을 잡으면 소리가 안 납니다.')) | Out-Null
    }

    $disabled = @($Endpoints | Where-Object { ($_.State -band 2) -eq 2 })
    if ($disabled.Count -gt 0) {
        $f.Add((New-Finding '정보' "사용 안 함으로 꺼둔 장치 $($disabled.Count)개" `
            (@($disabled | Select-Object -First 8 | ForEach-Object { "$($_.Flow) / $($_.Name) / $($_.Desc)" }) -join "`r`n") '')) | Out-Null
    }

    # --- 7d) What U Hear / 스테레오 믹스 같은 루프백 입력 ------------------
    $loopIn = @($Endpoints | Where-Object {
        $_.Flow -eq 'Capture' -and ($_.State -band 1) -eq 1 -and (Test-AnyMatch $_.Name $LoopbackCaptureNames)
    })
    foreach ($e in $loopIn) {
        if ($e.IsDefault -or $e.IsDefaultComms) {
            $f.Add((New-Finding '문제' "루프백 입력이 기본 녹음 장치로 잡혀 있음: $($e.Name)" `
                "$($e.Desc) / 이 장치는 마이크가 아니라 'PC에서 나는 소리 전체'를 그대로 되받는 입력입니다." `
                '디스코드·방송에 게임 소리가 이중으로 나가거나 하울링·에코가 생깁니다. 소리 설정 > 입력에서 실제 마이크 입력으로 바꿔주세요.')) | Out-Null
        }
        else {
            $f.Add((New-Finding '주의' "루프백 입력이 켜져 있음: $($e.Name)" `
                "$($e.Desc)" `
                '윤슬 표준은 소프트웨어 루프백을 쓰지 않고 OBS에서 소스별로 따로 잡습니다. 쓰는 앱이 없다면 소리 제어판에서 사용 안 함으로 꺼두는 게 안전합니다.')) | Out-Null
        }
    }

    # --- 7e) 캡처보드 (투컴 방송PC) ----------------------------------------
    if ($capCards.Count -gt 0) {
        $f.Add((New-Finding '정보' "캡처보드 감지됨 - 투컴 방송PC로 보입니다 ($($capCards.Count)대)" `
            (($capCards | ForEach-Object { $_.Label }) -join ', ') `
            '게임PC 소리는 이 캡처보드로 들어옵니다. OBS에서 캡처보드 오디오를 별도 소스로 잡고, 윈도우 기본 녹음 장치로는 지정하지 마세요.')) | Out-Null
    }
    $capDead = @($Groups | Where-Object { $_.Kind -eq '캡처보드' -and @($_.Endpoints | Where-Object { ($_.State -band 1) -eq 1 }).Count -eq 0 })
    if ($capDead.Count -gt 0) {
        $f.Add((New-Finding '주의' "캡처보드가 연결 해제 상태 ($($capDead.Count)대)" `
            (($capDead | ForEach-Object { $_.Label }) -join ', ') `
            '게임PC 화면·소리가 안 넘어옵니다. HDMI와 USB를 다시 꽂고, 게임PC가 켜진 상태인지 확인해 주세요.')) | Out-Null
    }

    # --- 7f) Creative Sound Blaster 전용 안내 ------------------------------
    $sb = @($Groups | Where-Object { $_.Kind -eq '게임 사운드카드' -and @($_.Endpoints | Where-Object { ($_.State -band 1) -eq 1 }).Count -gt 0 })
    if ($sb.Count -gt 0) {
        $f.Add((New-Finding '주의' "게임용 사운드카드 감지됨: $((($sb | ForEach-Object { $_.Label }) -join ', '))" `
            '이 계열은 드라이버 자체 음장 효과(SBX / Crystalizer / Smart Volume / Scout Mode)가 기본으로 켜져 있는 경우가 많습니다.' `
            '방송으로 나가는 소리가 출렁이거나 뭉개지는 원인입니다. Creative App(또는 Sound Blaster Command)에서 음장 효과를 전부 끄고(Direct 모드), 소리 제어판 > 고급의 샘플레이트를 다른 기기와 같은 값으로 맞춰주세요.')) | Out-Null
    }

    # --- 7g) 인터페이스 등급 ------------------------------------------------
    foreach ($g in $ifaceActive) {
        switch ($g.Grade) {
            'A' {
                $f.Add((New-Finding '정보' "$($g.Label): A급 (다중 서브믹스 + 자유 루프백)" `
                    '출력마다 독립된 믹스를 만들고 원하는 출력에 루프백을 걸 수 있습니다.' `
                    '방송용 / 노래방용 / 합주용 루프백을 동시에 운영하는 윤슬 표준 풀버전을 적용할 수 있습니다.')) | Out-Null
            }
            'B' {
                $f.Add((New-Finding '정보' "$($g.Label): B급 (전용 루프백 1개, 소스 선택 가능)" `
                    '루프백이 하나뿐이라 용도별로 나눌 수 없습니다.' `
                    '방송용 루프백 하나만 구성합니다. 노래방·합주용이 따로 필요하면 그때그때 소스를 바꿔 끼워야 합니다.')) | Out-Null
            }
            'C' {
                $f.Add((New-Finding '문제' "$($g.Label): C급 (고정 혼합 루프백) - 윤슬 표준 적용 불가" `
                    '입력과 재생을 무조건 섞어서 내보내는 방식이라, 방송에 나갈 소리만 골라낼 수 없습니다.' `
                    '이 기기로는 표준 라우팅을 만들 수 없습니다. 루프백 소스를 고를 수 있는 기기로 교체가 필요합니다.')) | Out-Null
            }
            default {
                $f.Add((New-Finding '주의' "$($g.Label): 등급 미확인" `
                    '이 기기의 루프백 방식이 아직 조사되지 않았습니다.' `
                    '믹서 앱에서 루프백에 실을 소스를 고를 수 있는지 확인해 주세요. 고를 수 있으면 표준 적용 가능, 무조건 섞이면 불가입니다.')) | Out-Null
            }
        }
    }

    # --- 7h) 앱별 출력 지정 -------------------------------------------------
    if (-not $script:IsDumpMode) {
        $apps = @()
        try { $apps = @(Get-AppAssignments) } catch { }
        $cur = @($apps | Where-Object { $_.Store -eq 'A' })
        $old = @($apps | Where-Object { $_.Store -eq 'B' })

        $epById = @{}
        foreach ($e in $Endpoints) { $epById[$e.Id] = $e }

        if ($cur.Count -eq 0) {
            $f.Add((New-Finding '주의' '앱별 출력이 하나도 지정되어 있지 않음' `
                '윈도우 볼륨 믹서에서 앱마다 출력 장치를 따로 지정한 기록이 없습니다.' `
                '이 상태면 모든 소리가 기본 장치 한 곳으로 몰립니다. 설정 > 시스템 > 소리 > 볼륨 믹서에서 앱마다 출력을 지정해 주세요.')) | Out-Null
        }
        else {
            $lines = @(); $offIface = @()
            foreach ($a in ($cur | Sort-Object App, Role)) {
                $e = $epById[$a.EndpointId]
                $target = if ($e) { "$($e.Name) ($($e.Desc))" } else { '알 수 없는 장치(삭제됨)' }
                $bad = -not ($e -and $ifaceEpIds.ContainsKey($e.Id))
                if ($bad -and $a.Role -eq '일반') { $offIface += "$($a.App) -> $target" }
                $lines += "$($a.App) [$($a.Role)] -> $target" + $(if ($bad) { '   <- 오인페가 아님' } else { '' })
            }
            $f.Add((New-Finding '정보' "앱별 출력 지정 $($cur.Count)건" ($lines -join "`r`n") '')) | Out-Null
            if ($offIface.Count -gt 0) {
                $f.Add((New-Finding '주의' "오인페가 아닌 장치로 지정된 앱 $($offIface.Count)개" ($offIface -join "`r`n") `
                    '이 앱들의 소리는 방송에 잡히지 않습니다. 의도한 게 아니면 볼륨 믹서에서 오인페 채널로 바꿔주세요.')) | Out-Null
            }
        }

        # 업데이트로 경로가 바뀌어 지정이 풀린 앱 찾기
        $stale = @()
        $running = @{}
        foreach ($proc in (Get-Process -ErrorAction SilentlyContinue)) {
            $pp = $null
            try { $pp = $proc.Path } catch { }
            if ($pp) { $running[$proc.ProcessName.ToLower() + '.exe'] = $pp }
        }
        $byApp = $apps | Group-Object App
        foreach ($g in $byApp) {
            $name = $g.Name.ToLower()
            if (-not $running.ContainsKey($name)) { continue }
            $nowKey = ConvertTo-AppKey $running[$name]
            $known = @($g.Group | ForEach-Object { $_.AppKey })
            if ($known -notcontains $nowKey) {
                $stale += "$($g.Name) : 지금 실행 경로가 지정 기록에 없음"
            }
        }
        if ($stale.Count -gt 0) {
            # 방송 라우팅에 실제로 영향을 주는 앱만 '문제'로 올린다
            $careAbout = @('discord', 'chrome', 'msedge', 'whale', 'firefox', 'obs64', 'obs32',
                           'syncroom', 'spotify', 'reaper', 'kakaotalk', 'steam', 'vlc', 'potplayer')
            $hot = @(); $cold = @()
            foreach ($line in $stale) {
                $nm = (($line -split ' :')[0]) -replace '\.exe$', ''
                if ($careAbout -contains $nm.ToLower()) { $hot += $line } else { $cold += $line }
            }
            if ($hot.Count -gt 0) {
                $f.Add((New-Finding '문제' "업데이트로 출력 지정이 풀린 앱 $($hot.Count)개" `
                    ($hot -join "`r`n") `
                    '이 앱들은 설치 경로에 버전 번호가 들어갑니다. 업데이트되면 윈도우가 다른 프로그램으로 인식해서 예전에 해둔 출력 지정이 통째로 풀립니다. 볼륨 믹서에서 다시 지정해 주세요. (디스코드가 대표적입니다)')) | Out-Null
            }
            if ($cold.Count -gt 0) {
                $f.Add((New-Finding '정보' "출력 지정 기록이 없는 앱 $($cold.Count)개" `
                    ($cold -join "`r`n") `
                    '방송 라우팅과 직접 상관없는 앱들입니다. 업데이트로 경로가 바뀌었거나 애초에 지정한 적이 없는 경우입니다.')) | Out-Null
            }
        }

        if ($old.Count -gt 0) {
            $f.Add((New-Finding '정보' "예전 앱 지정 기록 $($old.Count)건 (참고용)" `
                (@($old | Sort-Object App -Unique | Select-Object -First 12 |
                   ForEach-Object { "$($_.App)  [$($_.Device)]" }) -join "`r`n") `
                '윈도우가 예전 방식으로 쌓아둔 기록입니다. 지금 동작에는 영향이 적지만, 같은 앱이 여러 버전으로 남아 있으면 업데이트로 지정이 풀렸다는 신호입니다.')) | Out-Null
        }
    }

    # --- 8) 가상 오디오 장치 ----------------------------------------------
    $virt = @($Groups | Where-Object { $_.Kind -eq '가상 장치' -and @($_.Endpoints | Where-Object { ($_.State -band 1) -eq 1 }).Count -gt 0 })
    if ($virt.Count -gt 0) {
        $f.Add((New-Finding '주의' "가상 오디오 장치가 설치되어 있음 ($($virt.Count)개)" `
            (($virt | ForEach-Object { $_.Label }) -join ', ') `
            '가상 케이블류는 라우팅을 가로채는 경우가 있습니다. 쓰는 게 맞으면 그대로 두시고, 기억에 없다면 알려주세요.')) | Out-Null
    }

    return $f
}

# =====================================================================
# 6. 실행
# =====================================================================
$startedAt = Get-Date
Write-Host ''
Write-Host '  윤슬 라우팅 닥터 (진단 전용)' -ForegroundColor Cyan
Write-Host '  이 프로그램은 설정을 바꾸지 않고 읽기만 합니다.' -ForegroundColor DarkGray
Write-Host ''

$endpoints = $null
$mode = '실시간 진단'
$script:IsDumpMode = [bool]$FromDump
try {
    if ($FromDump) {
        $mode = "덤프 재분석 ($FromDump)"
        $endpoints = Get-EndpointsFromDump -Path $FromDump
    }
    else {
        $endpoints = Get-EndpointsFromSystem
    }
}
catch {
    Write-Host "  [실패] 오디오 장치를 읽지 못했습니다: $($_.Exception.Message)" -ForegroundColor Red
    if (-not $NoPause) { Read-Host '  엔터를 누르면 종료합니다' }
    exit 1
}

$endpoints = @($endpoints)
if ($endpoints.Count -eq 0) {
    Write-Host '  [실패] 오디오 엔드포인트가 하나도 없습니다. 오디오 드라이버 상태를 확인해 주세요.' -ForegroundColor Red
    if (-not $NoPause) { Read-Host '  엔터를 누르면 종료합니다' }
    exit 1
}

$groups = Get-DeviceGroups -Endpoints $endpoints

$setupAuto = $false
if ($Setup -eq 'Auto') { $Setup = Get-SetupMode -Groups $groups; $setupAuto = $true }
$setupLabel = switch ($Setup) {
    'Game'   { '투컴 - 게임PC' }
    'Stream' { '투컴 - 방송PC' }
    default  { '단일 PC' }
}
if ($setupAuto) { $setupLabel += ' (자동 판정)' }

$findings = Invoke-Diagnosis -Endpoints $endpoints -Groups $groups -Setup $Setup

$problems = @($findings | Where-Object { $_.Level -eq '문제' })
$warns    = @($findings | Where-Object { $_.Level -eq '주의' })
$oks      = @($findings | Where-Object { $_.Level -eq '정상' })
$infos    = @($findings | Where-Object { $_.Level -eq '정보' })

# ---- 헤더 ----
Write-Both '=====================================================================' 'DarkGray'
Write-Both " 윤슬 라우팅 진단 결과  (v$ScriptVersion)" 'Cyan'
Write-Both " 진단 시각 : $($startedAt.ToString('yyyy-MM-dd HH:mm:ss'))" 'DarkGray'
Write-Both " PC 이름   : $env:COMPUTERNAME / 사용자: $env:USERNAME" 'DarkGray'
Write-Both " 윈도우    : $([System.Environment]::OSVersion.VersionString)" 'DarkGray'
Write-Both " 진단 방식 : $mode" 'DarkGray'
Write-Both " 구성      : $setupLabel" 'DarkGray'
Write-Both '=====================================================================' 'DarkGray'
Write-Both ''

if ($problems.Count -eq 0 -and $warns.Count -eq 0) {
    Write-Both ' 종합: 표준 라우팅 기준으로 걸리는 항목이 없습니다.' 'Green'
} else {
    Write-Both " 종합: 문제 $($problems.Count)건 / 주의 $($warns.Count)건" $(if ($problems.Count -gt 0) { 'Red' } else { 'Yellow' })
}
Write-Both ''

# ---- 진단 항목 ----
function Show-Findings {
    param($Items, [string]$Head, [string]$Color)
    if ($Items.Count -eq 0) { return }
    Write-Both "---------------------------------------------------------------------" 'DarkGray'
    Write-Both " $Head" $Color
    Write-Both "---------------------------------------------------------------------" 'DarkGray'
    $i = 0
    foreach ($it in $Items) {
        $i++
        Write-Both ("  {0}. {1}" -f $i, $it.Title) $Color
        if ($it.Detail) { Write-Both ("     - " + ($it.Detail -replace "`r`n", "`r`n     - ")) 'Gray' }
        if ($it.Fix)    { Write-Both ("     > 조치: " + $it.Fix) 'White' }
        Write-Both ''
    }
}

Show-Findings $problems '[ 문제 ] 지금 소리 사고를 일으키는 항목' 'Red'
Show-Findings $warns    '[ 주의 ] 당장은 아니어도 손봐야 하는 항목' 'Yellow'
Show-Findings $oks      '[ 정상 ] 표준대로 맞춰져 있는 항목' 'Green'
Show-Findings $infos    '[ 참고 ] 알아두면 좋은 정보' 'DarkCyan'

# ---- 기기 목록 ----
Write-Both "---------------------------------------------------------------------" 'DarkGray'
Write-Both ' 감지된 오디오 기기' 'Cyan'
Write-Both "---------------------------------------------------------------------" 'DarkGray'
$primaryKinds = @('오디오 인터페이스', '게임 사운드카드', '캡처보드')
foreach ($g in ($groups | Sort-Object @{Expression={ if ($primaryKinds -contains $_.Kind) { 0 } else { 1 } }}, Label)) {
    $act = @($g.Endpoints | Where-Object { ($_.State -band 1) -eq 1 })
    $mark = if ($primaryKinds -contains $g.Kind) { '*' } else { ' ' }
    Write-Both ("  {0} {1}  [{2}]  활성 {3} / 전체 {4}" -f $mark, $g.Label, $g.Kind, $act.Count, $g.Endpoints.Count) `
        $(if ($primaryKinds -contains $g.Kind) { 'White' } else { 'DarkGray' })
    if ($g.Grade)    { Write-Both ("      등급    : " + $g.Grade + "급") 'DarkGray' }
    if ($g.Hardware) { Write-Both ("      하드웨어: " + $g.Hardware) 'DarkGray' }
    if ($g.Mixer)    { Write-Both ("      믹서 앱 : " + $g.Mixer) 'DarkGray' }
    foreach ($e in ($act | Sort-Object Flow, Name)) {
        $tag = @()
        if ($e.IsDefault)       { $tag += '기본' }
        if ($e.IsDefaultComms)  { $tag += '통신기본' }
        if ($e.Muted -eq 1)     { $tag += '음소거' }
        $tagStr = if ($tag.Count -gt 0) { ' <' + ($tag -join ',') + '>' } else { '' }
        $rate = if ($e.SampleRate -gt 0) { "$($e.SampleRate)Hz $($e.Channels)ch" } else { '-' }
        Write-Both ("        - [{0,-7}] {1,-24} {2}{3}" -f $e.Flow, $e.Name, $rate, $tagStr) 'Gray'
    }
    Write-Both ''
}

# ---- 기준선 비교 ----
if ($Compare -eq 'pick' -or ($Compare -and -not (Test-Path -LiteralPath $Compare))) {
    # 기준선 파일을 직접 고르게 한다 (드래그가 어려운 경우)
    $searchDirs = @([Environment]::GetFolderPath('Desktop'), $PSScriptRoot, $env:USERPROFILE,
                    (Join-Path $env:USERPROFILE 'Downloads')) | Where-Object { $_ -and (Test-Path $_) }
    $cands = @()
    foreach ($dir in ($searchDirs | Select-Object -Unique)) {
        $cands += @(Get-ChildItem -LiteralPath $dir -Filter 'routing-check_*.txt' -File -ErrorAction SilentlyContinue)
    }
    $cands = @($cands | Sort-Object LastWriteTime -Descending |
               Group-Object Name | ForEach-Object { $_.Group[0] } |
               Sort-Object LastWriteTime -Descending | Select-Object -First 10)

    if ($cands.Count -eq 0) {
        Write-Host ''
        Write-Host '  기준선으로 쓸 예전 진단 결과 파일을 찾지 못했습니다.' -ForegroundColor Yellow
        Write-Host '  (바탕화면 / 다운로드 / 이 폴더에서 routing-check_*.txt 를 찾습니다)' -ForegroundColor DarkGray
        $Compare = ''
    }
    else {
        Write-Host ''
        Write-Host '  기준선으로 쓸 파일을 고르세요 (최근 순)' -ForegroundColor Cyan
        Write-Host ''
        for ($i = 0; $i -lt $cands.Count; $i++) {
            Write-Host ("   {0}. {1}   [{2}]" -f ($i + 1), $cands[$i].Name,
                        $cands[$i].LastWriteTime.ToString('MM-dd HH:mm')) -ForegroundColor White
        }
        Write-Host ''
        $pick = Read-Host '  번호를 입력하고 엔터 (그냥 엔터 = 비교 안 함)'
        $n = 0
        if ([int]::TryParse($pick, [ref]$n) -and $n -ge 1 -and $n -le $cands.Count) {
            $Compare = $cands[$n - 1].FullName
            Write-Host ("  선택: " + $cands[$n - 1].Name) -ForegroundColor Green
        }
        else { $Compare = '' }
    }
}

if ($Compare) {
    if (Test-Path -LiteralPath $Compare) {
        try {
            $baseSnap = Get-ReportSnapshot -Path $Compare
            if ($baseSnap.Endpoints.Count -eq 0) {
                Write-Both " [주의] 기준선 파일에서 장치 목록을 읽지 못했습니다: $Compare" 'Yellow'
            } else {
                Show-Diff -Base $baseSnap -Endpoints $endpoints
            }
        } catch {
            Write-Both " [주의] 기준선 비교 실패: $($_.Exception.Message)" 'Yellow'
        }
    } else {
        Write-Both " [주의] 기준선 파일을 찾지 못했습니다: $Compare" 'Yellow'
    }
}

# ---- 로그 전용: 전체 덤프 ----
Write-Both "---------------------------------------------------------------------" 'DarkGray' -LogOnly
Write-Both ' 전체 엔드포인트 덤프 (기술 확인용)' 'DarkGray' -LogOnly
Write-Both "---------------------------------------------------------------------" 'DarkGray' -LogOnly
foreach ($flow in @('Render', 'Capture')) {
    Write-Both "=== $flow ===" 'DarkGray' -LogOnly
    foreach ($e in ($endpoints | Where-Object { $_.Flow -eq $flow } | Sort-Object Name)) {
        $line = "{0,-22}|{1,-22}|{2,6}Hz {3}ch|st={4,-10}|mute={5}|vol={6}|{7}|{8}" -f `
            $e.Name, $e.Desc, $e.SampleRate, $e.Channels, $e.State, $e.Muted,
            $(if ($e.Volume -ge 0) { Get-VolPct $e } else { '-' }),
            $e.HardwareId, $e.Id
        Write-Both $line 'DarkGray' -LogOnly
    }
    Write-Both '' 'DarkGray' -LogOnly
}

# ---- 로그 전용: 파인더(라우팅 가이드 앱)가 읽는 데이터 ----
Write-Both "=== YS-DATA (프로그램이 읽는 부분입니다. 지우지 마세요) ===" 'DarkGray' -LogOnly
Write-Both ("setup=" + $Setup) 'DarkGray' -LogOnly
Write-Both ("pc=" + $env:COMPUTERNAME) 'DarkGray' -LogOnly
Write-Both ("time=" + $startedAt.ToString('yyyy-MM-dd HH:mm:ss')) 'DarkGray' -LogOnly
Write-Both ("version=" + $ScriptVersion) 'DarkGray' -LogOnly
foreach ($g in $groups) {
    $act = @($g.Endpoints | Where-Object { ($_.State -band 1) -eq 1 })
    $rates = @($act | Where-Object { $_.SampleRate -gt 0 } | ForEach-Object { $_.SampleRate } | Sort-Object -Unique)
    $line = "{0}|{1}|{2}|{3}|{4}/{5}|{6}" -f $g.Kind, $g.Label, $g.Hardware, ($rates -join ','), $act.Count, $g.Endpoints.Count, $g.Grade
    if ($g.Kind -eq '오디오 인터페이스' -or $g.Kind -eq '게임 사운드카드') { Write-Both ("iface=" + $line) 'DarkGray' -LogOnly }
    elseif ($g.Kind -eq '캡처보드') { Write-Both ("capcard=" + $line) 'DarkGray' -LogOnly }
    elseif ($g.Kind -eq '가상 장치') { Write-Both ("virtual=" + $line) 'DarkGray' -LogOnly }
}
$defR = $endpoints | Where-Object { $_.Flow -eq 'Render'  -and $_.IsDefault } | Select-Object -First 1
$defC = $endpoints | Where-Object { $_.Flow -eq 'Capture' -and $_.IsDefault } | Select-Object -First 1
if ($defR) { Write-Both ("defaultRender=" + $defR.Name + "|" + $defR.Desc) 'DarkGray' -LogOnly }
if ($defC) { Write-Both ("defaultCapture=" + $defC.Name + "|" + $defC.Desc) 'DarkGray' -LogOnly }
foreach ($it in $problems) { Write-Both ("problem=" + $it.Title) 'DarkGray' -LogOnly }
foreach ($it in $warns)    { Write-Both ("warn=" + $it.Title) 'DarkGray' -LogOnly }
Write-Both "=== /YS-DATA ===" 'DarkGray' -LogOnly
Write-Both '' 'DarkGray' -LogOnly

# ---- 저장 ----
if (-not $OutFile) {
    $desktop = [Environment]::GetFolderPath('Desktop')
    if (-not $desktop -or -not (Test-Path $desktop)) { $desktop = $env:USERPROFILE }
    $OutFile = Join-Path $desktop ("routing-check_{0}_{1}_{2}.txt" -f $Setup, $env:COMPUTERNAME, $startedAt.ToString('yyyyMMdd-HHmmss'))
}
try {
    $script:Report -join "`r`n" | Out-File -LiteralPath $OutFile -Encoding UTF8 -Force
    Write-Host ''
    Write-Host ' 진단 결과 파일이 저장됐습니다:' -ForegroundColor Cyan
    Write-Host "   $OutFile" -ForegroundColor White
    Write-Host ' 이 파일을 그대로 보내주시면 됩니다.' -ForegroundColor DarkGray
}
catch {
    Write-Host " [주의] 결과 파일 저장 실패: $($_.Exception.Message)" -ForegroundColor Yellow
}

Write-Host ''
if (-not $NoPause) { Read-Host ' 엔터를 누르면 창이 닫힙니다' | Out-Null }
