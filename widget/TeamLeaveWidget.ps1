# TeamLeaveWidget-Package (이 줄은 자동 업데이트 확인용이니 지우지 마세요)
# TeamCal - 팀 휴가 + 내 일정 Windows 데스크톱 위젯
#  - 팀 휴가 캘린더 보기 + 휴가 등록 (팀 휴가 사이트와 같은 데이터)
#  - 내 일정: 구글 로그인(브라우저) 또는 iCal 주소
#  - 라이트/다크 테마, 투명도, 항상 위
# 사용법: 같은 폴더의 "TeamCal 설치.cmd" 를 더블클릭하세요. (또는 "exe 만들기.cmd" 로 만든 TeamCal-버전.exe)
param([switch]$Setup, [switch]$Uninstall)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing, Microsoft.VisualBasic, System.Net.Http

$AppName    = 'TeamCal'
$OldNames   = @('팀 휴가 위젯')      # 예전 바로가기 이름 (정리용)
$AppDir     = Join-Path $env:LOCALAPPDATA 'TeamLeaveWidget'
$LibDir     = Join-Path $AppDir 'lib'
$DataDir    = Join-Path $AppDir 'webdata'
$UiDir      = Join-Path $AppDir 'ui'
$StateFile  = Join-Path $AppDir 'state.json'
$GClientFile= Join-Path $AppDir 'google_client.json'
$GTokenFile = Join-Path $AppDir 'google_token.dat'
$GuideFile  = Join-Path $AppDir '구글 캘린더 연결 방법.txt'
$Installed  = Join-Path $AppDir 'TeamLeaveWidget.ps1'
$Launcher   = Join-Path $AppDir 'launch.vbs'
$StartupLnk = Join-Path ([Environment]::GetFolderPath('Startup')) "$AppName.lnk"
$DesktopLnk = Join-Path ([Environment]::GetFolderPath('Desktop')) "$AppName.lnk"
$Utf8       = New-Object System.Text.UTF8Encoding($false)
$SiteUrl    = 'https://pa-architect.github.io/team-leave/'
$AppVersion = '2.0.3'
$UpdateUrl  = 'https://none-hongcheol.github.io/TeamCal/widget/version.json'

function Write-Log($text) {
    try { Add-Content -LiteralPath (Join-Path $AppDir 'error.log') -Value ("[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $text) -Encoding UTF8 } catch { }
}
function Fail($msg) {
    Write-Log $msg
    [System.Windows.Forms.MessageBox]::Show($msg, $AppName, 'OK', 'Error') | Out-Null
    exit 1
}
function Fail-WebView($ex, $where) {
    $hr  = if ($ex) { '0x{0:X8}' -f $ex.HResult } else { '?' }
    $msg = if ($ex) { $ex.Message } else { '(알 수 없음)' }
    $ver = try { [Microsoft.Web.WebView2.Core.CoreWebView2Environment]::GetAvailableBrowserVersionString() } catch { '없음' }
    $hint = switch -Regex ($hr) {
        '8007139F' { '이전 위젯이 아직 실행 중일 수 있어요. 작업 관리자에서 powershell / msedgewebview2 를 모두 종료한 뒤 다시 실행해 보세요.' }
        '80070005' { "저장 폴더에 쓸 권한이 없어요. 백신 프로그램이 막고 있는지 확인해 주세요.`n($DataDir)" }
        '80070002' { 'WebView2 런타임 파일을 찾지 못했어요. WebView2 런타임을 다시 설치해 주세요.' }
        default    { 'WebView2 런타임을 최신 버전으로 설치(또는 복구)한 뒤 다시 실행해 보세요.' }
    }
    Write-Log "$where 실패 | HRESULT $hr | 런타임 $ver | $msg | $($ex | Out-String)"
    $r = [System.Windows.Forms.MessageBox]::Show("$where 을(를) 시작하지 못했습니다.`n`n$hint`n`n오류 코드: $hr`n런타임 버전: $ver`n내용: $msg`n`n'예'를 누르면 WebView2 설치 페이지가 열립니다.`n(자세한 기록: $AppDir\error.log)", $AppName, 'YesNo', 'Error')
    if ($r -eq 'Yes') { Start-Process 'https://developer.microsoft.com/microsoft-edge/webview2/#download' }
    exit 1
}

# ---------------- 위젯 화면 (HTML) ----------------
$WidgetHtml = @'
<!doctype html>
<html lang="ko">
<head>
<meta charset="utf-8">
<title>TeamCal</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=IBM+Plex+Sans+KR:wght@400;500;600;700&display=swap">
<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.117.3/dist/umd/supabase.js"></script>
<style>
:root{
  --bg:#fbfaf7; --fg:#1b1b1d; --muted:#6b6b70; --line:#ebe8e1; --sel:#f0ede6; --field:#ffffff;
  --dot:#cfcbc2; --dotoff:#e2ded6; --past:#1b1b1d; --sun:#c8463b; --sat:#3a62c9; --accent:#e0592a;
  --scrim:rgba(27,27,29,.28); --err:#c23b2f; --ok:#178a6b; --bar:#9d978c; --barout:#b9b3a8;
  --font:"IBM Plex Sans KR","Malgun Gothic",system-ui,sans-serif;
  color-scheme:light;
}
body[data-theme="dark"]{
  --bg:#111113; --fg:#f2f2f0; --muted:#a0a0a7; --line:#26262b; --sel:#1f1f24; --field:#18181c;
  --dot:#3a3a41; --dotoff:#2b2b31; --past:#f2f2f0; --sun:#ff7a6b; --sat:#8fa8ff; --accent:#ff8a4c;
  --scrim:rgba(0,0,0,.5); --err:#ff7a6b; --ok:#4fd1a5; --bar:#a3a3ae; --barout:#7c7c88;
  color-scheme:dark;
}
*{box-sizing:border-box}
html,body{margin:0;background:var(--bg);color:var(--fg);font-family:var(--font);-webkit-font-smoothing:antialiased;overflow:hidden}
[hidden]{display:none!important}
body.fixed{overflow:hidden}
body.fixed::-webkit-scrollbar{width:6px} body.fixed::-webkit-scrollbar-thumb{background:var(--dot);border-radius:3px}
.rz{position:fixed;z-index:20;app-region:no-drag;-webkit-app-region:no-drag}
.rz.r{top:0;right:0;bottom:14px;width:5px;cursor:ew-resize}
.rz.l{top:0;left:0;bottom:14px;width:5px;cursor:ew-resize}
.rz.b{left:14px;right:14px;bottom:0;height:5px;cursor:ns-resize}
.rz.br{right:0;bottom:0;width:14px;height:14px;cursor:nwse-resize}
.rz.bl{left:0;bottom:0;width:14px;height:14px;cursor:nesw-resize}
.rz.br::after{content:"";position:absolute;right:3px;bottom:3px;width:6px;height:6px;border-right:1.5px solid var(--dot);border-bottom:1.5px solid var(--dot);border-bottom-right-radius:2px}
button{font:inherit;color:inherit}
button:focus-visible,input:focus-visible{outline:2px solid var(--accent);outline-offset:2px}
#card{position:relative;display:flex;flex-direction:column;gap:18px;padding:14px 18px 18px;background:var(--bg)}

/* header */
#hd{position:sticky;top:0;z-index:20;margin:-14px -18px -8px;padding:14px 18px 8px;background:var(--bg);display:flex;align-items:center;gap:2px;app-region:drag;-webkit-app-region:drag;cursor:grab;user-select:none}
#hd button,#hd .sep{app-region:no-drag;-webkit-app-region:no-drag}
.mon{display:flex;align-items:baseline;gap:6px;flex:1;min-width:0;margin-right:4px}
.mon span{overflow:hidden;text-overflow:ellipsis}
.mon b{font-size:22px;font-weight:700;letter-spacing:-.02em;font-variant-numeric:tabular-nums}
.mon span{font-size:12px;color:var(--muted);font-weight:500;white-space:nowrap}
.ib{width:26px;height:26px;display:flex;align-items:center;justify-content:center;border:0;border-radius:13px;background:transparent;color:var(--muted);cursor:pointer;padding:0}
.ib:hover{background:var(--sel);color:var(--fg)}
.ib.on{color:var(--accent)}
.ib svg{width:13px;height:13px}
.sep{width:1px;height:14px;background:var(--line);margin:0 4px}

/* calendar */
.dow{display:grid;grid-template-columns:repeat(7,minmax(0,1fr));margin-bottom:6px}
.dow div{text-align:center;font-size:11px;font-weight:600;letter-spacing:.04em;color:var(--muted)}
.dow div:first-child{color:var(--sun)}
.grid{display:grid;grid-template-columns:repeat(7,minmax(0,1fr));row-gap:2px}
.cell{height:54px;border:0;padding:0;margin:0;border-radius:10px;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:5px;background:transparent;cursor:pointer}
.cell:hover{background:var(--sel)}
.cell.sel{background:var(--sel)}
.cell.today{box-shadow:inset 0 0 0 1.5px var(--accent)}
.cell.out{visibility:hidden;pointer-events:none}
.cell .n{opacity:.55;font-size:12px;line-height:1;font-variant-numeric:tabular-nums;font-weight:500;color:var(--muted)}
.cell.has .n{opacity:1;font-weight:700;color:var(--fg)}
.cell.today .n{opacity:1;color:var(--accent);font-weight:700}
.cell.red .n{color:var(--sun)}
.cell.sat .n{color:var(--sat)}
.dots{display:flex;gap:3px;height:8px;align-items:center}
.tb{display:flex;gap:2px;height:3px}
.tb{height:4px}
.tb i{width:12px;height:4px;border-radius:2px;background:var(--bar)}
.tb i.me{background:var(--accent);opacity:1}
.tb i.out{border-radius:0;background:repeating-linear-gradient(90deg,var(--barout) 0 2px,transparent 2px 4px);box-shadow:none}
/* 넓을 때: 칸 안에 일정 제목 */
.grid.wide .cell{height:auto;min-height:86px;align-items:stretch;justify-content:flex-start;padding:5px 4px 6px;gap:3px}
.grid.wide .cell .n{align-self:flex-start;padding-left:3px}
.evs{display:flex;flex-direction:column;gap:2px;min-width:0}
.ec{display:block;font-size:10.5px;line-height:1.4;padding:0 4px 0 5px;border-radius:4px;background:color-mix(in srgb,var(--c) 14%,transparent);border-left:2px solid var(--c);white-space:nowrap;overflow:hidden;text-overflow:ellipsis;color:var(--fg);text-align:left}
.ec.dn{opacity:.5;text-decoration:line-through}
.ec.more{background:none;border:0;color:var(--muted);padding-left:5px}
.grid.wide .tb{align-self:flex-start;padding-left:3px;margin-top:auto}
.lv{display:flex;align-items:center;gap:8px;font-size:12.5px;color:var(--muted);min-width:0}
.lv i{width:16px;height:4px;border-radius:2px;background:var(--bar);flex:none}
.lv i.me{background:var(--accent);opacity:1}
.lv i.out{border-radius:0;background:repeating-linear-gradient(90deg,var(--barout) 0 2px,transparent 2px 4px);box-shadow:none}
.lv.out .ti{opacity:.75}
.lv .tm{flex:0 0 44px;font-size:11.5px}
.lv .ti{flex:1;min-width:0;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
#ntBox:empty{display:none}
.nt{border-radius:12px;background:var(--sel);padding:10px 12px;font-size:12px;line-height:1.5}
.nt .h{display:flex;align-items:center;gap:6px;font-weight:700;font-size:12px;min-width:0}
.nt .h i{width:8px;height:8px;border-radius:50%;flex:none;background:var(--c)}
.nt .h b{flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.nt .h small{font-weight:400;color:var(--muted);font-size:10.5px;flex:none}
.nt ul{margin:4px 0 6px;padding-left:15px}.nt li{margin:1px 0}
.nt li i{display:inline-block;width:6px;height:6px;border-radius:50%;background:var(--c);margin-right:4px;vertical-align:1px}
.nt li b{font-weight:600}.nt li span{color:var(--muted)}
.nt .a{display:flex;gap:12px;font-size:11.5px}
.nt .a button{border:0;background:none;padding:0;font:inherit;font-weight:600;color:var(--accent);cursor:pointer}
.nt .a button.g{color:var(--muted);font-weight:500}
.nt .a button:hover{text-decoration:underline}
.legrow{display:flex;align-items:center;gap:8px;margin-top:8px}
.leg{display:flex;flex-wrap:wrap;gap:4px 14px;font-size:11px;color:var(--muted);flex:1;min-width:0}
.rf{margin-left:auto;flex:none;height:24px;display:inline-flex;align-items:center;gap:4px;padding:0 6px 0 4px;border:0;border-radius:12px;background:transparent;color:var(--muted);font-size:11px;cursor:pointer;font-family:inherit}
.rf:hover{background:var(--sel);color:var(--fg)}
.rf svg{width:14px;height:14px}
.rf.spin svg{animation:rfspin .8s linear infinite;color:var(--accent)}
@keyframes rfspin{to{transform:rotate(360deg)}}
.leg span{display:inline-flex;align-items:center;gap:5px}
.leg .d{width:8px;height:8px}
.leg i.bar{display:inline-block;width:12px;height:4px;border-radius:2px;background:var(--bar)}
.leg i.bar.me{background:var(--accent)}
.leg i.bar.out{border-radius:0;background:repeating-linear-gradient(90deg,var(--barout) 0 2px,transparent 2px 4px);box-shadow:none}
.d{width:8px;height:8px;border-radius:50%;background:var(--c)}
.d.h{background:linear-gradient(90deg,var(--c) 50%,transparent 50%);box-shadow:inset 0 0 0 1.2px var(--c)}
.d.e{width:5px;height:5px;background:var(--dotoff)}
.d.e.off{background:var(--dotoff)}
.d.e.past{background:var(--dot)}
.more{font-size:8.5px;color:var(--muted);line-height:1}

/* sections */
.sec{display:flex;flex-direction:column;gap:8px;padding-top:14px;border-top:1px solid var(--line)}
.sh{display:flex;align-items:center;gap:8px;min-height:26px}
.sh .t{font-size:12px;font-weight:700;letter-spacing:.02em}
.sh .c{font-size:11px;color:var(--muted);margin-left:auto}
.ch{width:22px;height:22px;flex:none;border:0;border-radius:11px;background:none;color:var(--muted);display:inline-flex;align-items:center;justify-content:center;cursor:pointer;padding:0}
.ch:hover{background:var(--sel);color:var(--fg)}
.ch svg{width:13px;height:13px;transition:transform .15s}
.ch[aria-expanded="false"] svg{transform:rotate(-90deg)}
.colsum{font-size:11px;color:var(--muted);font-weight:500;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;min-width:0}
.colsum:empty{display:none}
#calHd{margin-bottom:6px}#calHd .t{flex:1}
#calWrap.col #calBody{display:none}#calWrap.col #calHd{margin-bottom:0}
#daySec.col>:not(.sh),#gSec.col>:not(.sh){display:none!important}
#gSec.col .lo{display:none}
.calchips:empty{display:none}.calchips{margin-top:12px;display:flex;flex-direction:column;gap:8px}.calchips .gsub{margin:2px 0 -2px}
.gup{overflow-y:auto;overscroll-behavior:contain;margin-right:-10px;padding-right:6px;display:flex;flex-direction:column;gap:inherit}
.gup.fade{-webkit-mask-image:linear-gradient(#000 calc(100% - 28px),transparent);mask-image:linear-gradient(#000 calc(100% - 28px),transparent)}
.gup{scrollbar-width:none}.gup::-webkit-scrollbar{width:0}.gup::-webkit-scrollbar-thumb{background:var(--dot);border-radius:3px}.gup::-webkit-scrollbar-track{background:transparent}
.gp{margin-left:auto;height:18px;display:inline-flex;align-items:center;gap:3px;padding:0 6px 0 5px;border:1px solid var(--line);border-radius:9px;background:transparent;color:var(--muted);font-size:9.5px;font-weight:600;font-family:inherit;cursor:pointer;white-space:nowrap}
.gp svg{width:9px;height:9px;flex:none}
.gp .ar{font-weight:400;font-size:9px}
.gp:hover{color:var(--fg);border-color:var(--dot)}
.gp[hidden]{display:none}
.pill{height:26px;display:inline-flex;align-items:center;gap:4px;padding:0 10px 0 8px;border-radius:13px;border:1px solid var(--line);background:transparent;font-size:11.5px;font-weight:600;cursor:pointer}
.pill:hover{border-color:var(--fg)}
.pill svg{width:12px;height:12px;stroke:var(--accent)}
.list{display:flex;flex-direction:column;gap:6px;margin:0;padding:0;list-style:none}
.row{display:flex;align-items:center;gap:8px;font-size:13px;min-width:0}
.row .d{flex:none;width:8px;height:8px}
.row .nm{font-weight:600;white-space:nowrap}
.row .ty{font-size:11.5px;color:var(--muted);margin-left:auto;white-space:nowrap}
.row .memo{font-size:11px;color:var(--muted);overflow:hidden;text-overflow:ellipsis;white-space:nowrap;min-width:0;flex:1}
.del{height:22px;padding:0 8px;border-radius:11px;border:1px solid var(--line);background:transparent;font-size:11px;color:var(--muted);cursor:pointer;flex:none}
.del.arm{border-color:var(--err);color:var(--err)}
.empty{font-size:12px;color:var(--muted)}
.ev{display:flex;gap:8px;font-size:13px;min-width:0}
.ev .d{width:7px;height:7px;flex:none;margin-top:6px}
.ev .tm{padding-top:1px}
.ev .tm{flex:0 0 44px;font-size:11.5px;color:var(--muted);font-variant-numeric:tabular-nums;padding-top:1px;white-space:nowrap}
.ev .ti{flex:1;min-width:0;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.ev.past{opacity:.45}
.ev{align-items:flex-start}
.ck{width:16px;height:16px;flex:none;margin-top:2px;padding:0;border-radius:50%;border:1.6px solid var(--c);background:transparent;cursor:pointer;display:flex;align-items:center;justify-content:center;color:#fff}
.ck svg{width:10px;height:10px;opacity:0}
.ck[aria-checked="true"]{background:var(--c)}
.ck[aria-checked="true"] svg{opacity:1}
.ev.edit{cursor:pointer;border-radius:8px}
.ev.edit:hover .ti{text-decoration:underline;text-decoration-color:var(--line);text-underline-offset:3px}
.ev.edit:focus-visible{outline:2px solid var(--accent);outline-offset:2px}
.btn.danger{color:var(--err);border-color:var(--line)}
.btn.danger.arm{background:var(--err);color:#fff;border-color:var(--err)}
.ev.done .ti{text-decoration:line-through;color:var(--muted)}
.ev.done .tm{opacity:.6}
.evx{flex:none;height:20px;min-width:20px;padding:0 4px;margin-top:0;border:0;border-radius:10px;background:transparent;color:var(--muted);font-size:13px;line-height:1;cursor:pointer;opacity:0}
.ev:hover .evx,.evx:focus-visible,.evx.arm{opacity:1}
.evx:hover{background:var(--sel);color:var(--fg)}
.evx.arm{background:var(--err);color:#fff;font-size:11px;font-weight:700;padding:0 8px}
.lo{background:none;border:0;padding:2px 0;color:var(--muted);font-size:11px;cursor:pointer;text-decoration:underline;text-underline-offset:2px;text-decoration-color:var(--line)}
.lo:hover{color:var(--fg)}
.gbtn{height:42px;display:flex;align-items:center;justify-content:center;gap:10px;border-radius:12px;border:1px solid var(--line);background:#ffffff;color:#1b1b1d;font-size:13.5px;font-weight:600;cursor:pointer}
.gbtn:hover{border-color:#c9c5bc}
.gbtn svg{width:16px;height:16px}
.gblk{display:flex;flex-direction:column;gap:10px}
.upd{display:flex;align-items:center;gap:8px;padding:8px 10px 8px 12px;border-radius:12px;background:var(--sel);font-size:12px}
.upd i{width:7px;height:7px;border-radius:50%;background:var(--accent);flex:none}
.upd span{flex:1;min-width:0}
.upd button{height:28px;padding:0 12px;border-radius:14px;border:0;background:var(--fg);color:var(--bg);font-size:11.5px;font-weight:700;cursor:pointer}
.upd button:disabled{opacity:.6;cursor:default}
.abs{display:flex;align-items:center;gap:8px;padding:8px 10px;border-radius:10px;background:var(--sel);font-size:11.5px;color:var(--muted);min-width:0}
.absh{display:flex;align-items:center;gap:8px;flex:1;min-width:0;background:none;border:0;padding:0;color:inherit;font-size:inherit;text-align:left;cursor:pointer}
.absh b{font-weight:600;flex:none}
.absh span{flex:1;min-width:0;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.absh::after{content:"▾";font-size:10px;flex:none;opacity:.7}
.absh[aria-expanded="true"]::after{content:"▴"}
.lnk{background:none;border:0;padding:0;color:var(--muted);font-size:11.5px;text-decoration:underline;text-underline-offset:2px;cursor:pointer;flex:none}
.lnk:hover{color:var(--fg)}
.tg{height:22px;display:inline-flex;align-items:center;gap:5px;padding:0 8px 0 4px;border-radius:11px;border:1px solid var(--line);background:var(--bg);color:var(--muted);font-size:11px;font-weight:600;cursor:pointer;flex:none}
.tg i{width:22px;height:14px;border-radius:7px;background:var(--dot);position:relative;flex:none;transition:background .15s}
.tg i::after{content:"";position:absolute;top:2px;left:2px;width:10px;height:10px;border-radius:50%;background:#fff;transition:transform .15s}
.tg[aria-checked="true"]{color:var(--fg)}
.tg[aria-checked="true"] i{background:var(--fg)}
.tg[aria-checked="true"] i::after{transform:translateX(8px);background:var(--bg)}
.dayev{display:flex;flex-direction:column;gap:7px}
.dayev .ev{font-size:13.5px}
.dayev .ev .ti{font-weight:600}
.tlist{display:flex;flex-direction:column;gap:2px;max-height:52vh;overflow-y:auto;margin:0 -6px;padding:0 6px}
.trow{display:flex;align-items:center;gap:12px;height:40px;padding:0 6px;margin:0 -6px;border:0;border-radius:10px;background:transparent;font-size:13.5px;font-weight:500;text-align:left;cursor:pointer}
.trow:hover{background:var(--sel)}
.trow .bx{width:18px;height:18px;flex:none;border-radius:5px;box-sizing:border-box;border:2px solid var(--c);display:flex;align-items:center;justify-content:center}
.trow .bx svg{width:12px;height:12px;opacity:0}
.trow[aria-checked="true"] .bx{background:var(--c);border:0}
.trow[aria-checked="true"] .bx svg{opacity:1}
.trow small{margin-left:auto;font-size:11px;color:var(--muted)}
.tact{display:flex;align-items:center;gap:12px;font-size:12px;color:var(--muted)}
.tact span{margin-left:auto}
.cchips{display:flex;flex-wrap:wrap;gap:6px;margin-bottom:4px}
.cchip{height:28px;max-width:100%;display:inline-flex;align-items:center;gap:6px;padding:0 11px 0 9px;border-radius:14px;border:1px solid var(--line);background:transparent;color:var(--muted);font-size:12px;font-weight:500;cursor:pointer;min-width:0}
.cchip span:last-child{overflow:hidden;text-overflow:ellipsis;white-space:nowrap;max-width:150px}
.cchip i{width:8px;height:8px;border-radius:50%;flex:none;box-sizing:border-box;border:1.5px solid var(--c)}
.cchip[aria-checked="true"]{background:var(--sel);color:var(--fg);font-weight:600}
.cchip[aria-checked="true"] i{background:var(--c)}
.cchip.add{border-style:dashed;border-color:var(--dot);color:var(--muted);padding:0 11px 0 8px}
.cchip.add svg{width:11px;height:11px;stroke:var(--accent)}
.cchip.add:hover{color:var(--fg);border-color:var(--fg)}
.ipop .sw2{display:flex;gap:8px;margin-top:8px}
.ipop .sw2 button{width:22px;height:22px;border-radius:50%;border:0;background:var(--c);cursor:pointer;box-shadow:0 0 0 2px var(--bg)}
.ipop .sw2 button[aria-checked="true"]{box-shadow:0 0 0 2px var(--bg),0 0 0 4px var(--c)}
.ipop .msg2{margin:8px 0 0;font-size:11.5px;color:var(--muted);min-height:0}
.ipop .msg2.err{color:#d23c3c}
.ipop .act2{display:flex;justify-content:flex-end;gap:6px;margin-top:10px}
.ipop .act2 button{height:30px;padding:0 13px;border-radius:8px;font-size:12px;font-weight:600;cursor:pointer;font-family:inherit;border:1px solid var(--line);background:transparent;color:var(--fg)}
.ipop .act2 .pri{background:var(--fg);color:var(--bg);border-color:var(--fg)}
.gday{font-size:10.5px;font-weight:700;color:var(--muted);letter-spacing:.03em;margin-top:2px}
.gday.today{color:var(--accent)}
.btnrow{display:flex;gap:6px;flex-wrap:wrap}
.btn{height:34px;padding:0 14px;border-radius:10px;border:1px solid var(--line);background:transparent;font-size:12.5px;font-weight:600;cursor:pointer}
.btn.pri{background:var(--fg);color:var(--bg);border-color:var(--fg)}
.btn:disabled{opacity:.5;cursor:default}

/* year */
.yr{display:flex;flex-direction:column;gap:6px}
.yb{display:flex;gap:3px}
#yrYear{display:flex;flex-direction:column;gap:6px}
.dlbox{display:flex;flex-direction:column;gap:12px}.dlbox:empty{display:none}
.dli{display:flex;flex-direction:column;gap:6px;cursor:pointer;border:0;background:none;padding:0;text-align:left;font:inherit;color:inherit;width:100%}
.dlh{display:flex;align-items:center;gap:6px;font-size:11.5px;font-weight:600;min-width:0}
.dlh i{width:7px;height:7px;border-radius:50%;flex:none;background:var(--c)}
.dlh .nm{flex:none;max-width:45%;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.dlh .tt{min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;font-weight:500;color:var(--muted)}
.dlh .tt::before{content:"· ";}
.dlh b{margin-left:auto;font-size:12px;color:var(--accent);font-variant-numeric:tabular-nums;flex:none}
.dlh b.past{color:var(--muted)}
.dlh .off{flex:none;width:18px;height:18px;border-radius:9px;display:none;align-items:center;justify-content:center;color:var(--muted)}
.dli:hover .dlh .off,.dli:focus-within .dlh .off{display:inline-flex}.dlh .off:hover{background:var(--sel);color:var(--fg)}
.dli .yb span.now{background:var(--c)}
.yb span{flex:1;height:4px;border-radius:2px;background:var(--dot)}
.yb span.done{background:var(--fg);opacity:.85}
.yb span.now{background:var(--accent)}
.yl{display:flex;justify-content:space-between;font-size:10px;color:var(--muted);font-variant-numeric:tabular-nums}

/* login */
.login{display:flex;flex-direction:column;gap:12px;padding:6px 0 4px}
.login h2{margin:0;font-size:16px;font-weight:700}
.login p{margin:0;font-size:12px;color:var(--muted);line-height:1.6}
label{display:flex;flex-direction:column;gap:5px;font-size:11px;font-weight:600;color:var(--muted);min-width:0}
input{height:40px;width:100%;min-width:0;padding:0 10px;border-radius:10px;border:1px solid var(--line);background:var(--field);color:var(--fg);font:inherit;font-size:13px;font-weight:500}
.msg{margin:0;font-size:12px;min-height:1em;color:var(--muted)}
.msg.err{color:var(--err)} .msg.ok{color:var(--ok)}
.link{background:none;border:0;padding:0;color:var(--muted);font-size:12px;text-decoration:underline;text-underline-offset:3px;cursor:pointer;align-self:flex-start}

/* settings */
.sets{gap:0}
.stabs{display:flex;gap:2px;margin:10px -16px 0;padding:0 10px;border-bottom:1px solid var(--line);overflow-x:auto}
.stabs button{flex:none;padding:7px 9px 9px;border:0;border-bottom:2px solid transparent;background:none;color:var(--muted);font:inherit;font-size:12.5px;font-weight:600;cursor:pointer}
.stabs button[aria-selected="true"]{color:var(--fg);border-color:var(--fg)}
.sgrp{font-size:11px;font-weight:700;color:var(--muted);margin:14px 0 2px}
.srow{display:flex;align-items:center;gap:10px;padding:9px 0;border-bottom:1px solid var(--line);font-size:13px}
.srow:last-child{border-bottom:0}
.srow .st{flex:1;min-width:0}.srow .st small{display:block;color:var(--muted);font-size:11px;margin-top:1px;line-height:1.4}
.ssw{width:34px;height:20px;border-radius:10px;border:0;padding:0;background:var(--dot);position:relative;flex:none;cursor:pointer}
.ssw::after{content:"";position:absolute;top:2px;left:2px;width:16px;height:16px;border-radius:50%;background:#fff;box-shadow:0 1px 2px rgba(0,0,0,.2);transition:left .15s}
.ssw[aria-checked="true"]{background:var(--accent)}.ssw[aria-checked="true"]::after{left:16px}
.sseg{display:flex;background:var(--sel);border-radius:9px;padding:2px;flex:none}
.sseg button{padding:4px 10px;font:inherit;font-size:11.5px;border:0;border-radius:7px;background:none;color:var(--muted);font-weight:600;cursor:pointer}
.sseg button[aria-checked="true"]{background:var(--bg);color:var(--fg);box-shadow:0 1px 2px rgba(0,0,0,.08)}
.srange{display:flex;align-items:center;gap:8px;flex:none;width:150px}
.srange input{flex:1;accent-color:var(--accent)}.srange em{font-style:normal;font-size:11.5px;color:var(--muted);width:32px;text-align:right}
.sbtn{height:28px;padding:0 11px;border-radius:8px;border:1px solid var(--line);font:inherit;font-size:12px;font-weight:600;background:transparent;color:var(--fg);cursor:pointer;flex:none;white-space:nowrap}
.sbtn:hover{border-color:var(--dot)}.sbtn.pri{background:var(--fg);color:var(--bg);border-color:var(--fg)}.sbtn.dng{color:var(--err)}
.sacct{display:flex;align-items:center;gap:10px;padding:10px 12px;border-radius:12px;background:var(--sel);margin:6px 0 2px;font-size:13px}
.sacct .av{width:30px;height:30px;border-radius:50%;background:var(--accent);color:#fff;display:flex;align-items:center;justify-content:center;font-weight:700;flex:none}
.sacct .st{flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis}.sacct small{display:block;color:var(--muted);font-size:11px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.sbtns{display:flex;flex-wrap:wrap;gap:6px;margin:8px 0 2px}
.sft{display:flex;justify-content:space-between;margin:12px -16px -16px;padding:10px 16px 12px;border-top:1px solid var(--line);font-size:11px;color:var(--muted)}
body.popup .sft{margin-bottom:-16px}
/* sheet */
.dlg{max-height:100%;overflow-y:auto;display:flex;flex-direction:column;gap:13px;padding:16px;border-radius:20px;background:var(--bg);border:1px solid var(--line);box-shadow:0 24px 48px rgba(0,0,0,.22),0 4px 12px rgba(0,0,0,.08)}
.grab{display:none}
.dh{display:flex;align-items:center}
.dh b{flex:1;font-size:16px;font-weight:700;letter-spacing:-.01em}
.x{width:30px;height:30px;display:flex;align-items:center;justify-content:center;border:0;border-radius:15px;background:var(--sel);color:var(--muted);cursor:pointer;padding:0}
.chips{display:flex;flex-wrap:wrap;gap:6px}
.chip{height:30px;padding:0 11px;border-radius:15px;border:1px solid var(--line);background:transparent;font-size:12px;font-weight:500;cursor:pointer}
.chip.on{background:var(--fg);color:var(--bg);border-color:var(--fg);font-weight:600}
.two{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:8px}
.calc{font-size:12px;font-variant-numeric:tabular-nums;color:var(--muted)}
.calc.err{color:var(--err)}
.acts{display:flex;gap:8px}
.acts .btn{height:44px;font-size:13.5px;border-radius:12px}
.acts .btn:first-child{flex:1} .acts .btn:last-child{flex:2}
select{height:40px;width:100%;min-width:0;padding:0 8px;border-radius:10px;border:1px solid var(--line);background:var(--field);color:var(--fg);font:inherit;font-size:13px;font-weight:500}
.check{flex-direction:row;align-items:center;gap:8px;font-size:12.5px;font-weight:600;color:var(--fg);cursor:pointer}
.check input{width:18px;height:18px;accent-color:var(--fg)}
.sheet{position:fixed;inset:0;display:flex;flex-direction:column;justify-content:center;padding:14px;background:var(--scrim);z-index:5}
body.popup{overflow-y:auto}
body.popup #card{padding:0;gap:0;min-height:0}
body.popup #card>*:not(.sheet){display:none!important}
body.popup .sheet{position:static;padding:0;background:none;display:block}
body.popup .sheet[hidden]{display:none!important}
body.popup .dlg{border:0;border-radius:0;box-shadow:none;max-height:none;overflow:visible;padding:8px 16px 16px}
body.popup .grab{display:block;width:44px;height:14px;align-self:center;border-radius:0;background:radial-gradient(circle,var(--muted) 1.5px,transparent 1.8px) 0 0/7.5px 7px;opacity:.55;cursor:grab}
body.popup .grab,body.popup .dh{app-region:drag;-webkit-app-region:drag}
body.popup .dh button{app-region:no-drag;-webkit-app-region:no-drag}
body.popup .rz{display:none}
.fld{display:flex;flex-direction:column;gap:7px}
.flbl{font-size:11px;font-weight:600;color:var(--muted)}
.chip.add{border-style:dashed;border-color:var(--dot);font-weight:600;display:inline-flex;align-items:center;gap:4px}
.chip.add svg{width:12px;height:12px;stroke:var(--accent)}
.newcal{display:flex;flex-direction:column;gap:10px;padding:12px;border-radius:12px;background:var(--sel)}
.sw{display:flex;align-items:center;gap:10px}
.sw button{width:24px;height:24px;border-radius:50%;border:0;padding:0;cursor:pointer;background:var(--c)}
.sw button[aria-checked="true"]{box-shadow:0 0 0 2px var(--bg),0 0 0 4px var(--c)}
.nact{display:flex;gap:6px;justify-content:flex-end}
.btn.sm{height:32px;padding:0 12px;font-size:12px;border-radius:9px}
.gsub{font-size:11px;color:var(--muted);margin:6px 0 6px;font-weight:600}
.thint{position:relative;border:1px dashed var(--dot);border-radius:12px;padding:10px 30px 10px 12px;margin:2px 0 12px;font-size:11.5px;line-height:1.6;color:var(--muted)}
.thint b{color:var(--fg);font-size:12px;display:block;margin-bottom:3px}
.thint ol{margin:0;padding-left:16px}
.thint .lk{border:0;background:none;padding:0;color:var(--accent);font-weight:600;font-size:11.5px;cursor:pointer;font-family:inherit}
.thint .lk:hover{text-decoration:underline}
.thint .x2{position:absolute;right:6px;top:6px;width:22px;height:22px;border:0;border-radius:50%;background:none;color:var(--muted);cursor:pointer;display:flex;align-items:center;justify-content:center}
.thint .x2:hover{background:var(--sel);color:var(--fg)}
.ipop{position:absolute;left:10px;right:10px;z-index:40;background:var(--bg);border:1px solid var(--line);border-radius:14px;box-shadow:0 10px 30px rgba(0,0,0,.2);padding:13px 13px 12px;font-size:12.5px;color:var(--fg)}
.ipop .ih{display:flex;align-items:center;gap:8px;font-weight:700;font-size:13.5px;min-width:0}
.ipop .ih i{width:10px;height:10px;border-radius:50%;flex:none;background:var(--c)}
.ipop .ih span{flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.ipop .il{color:var(--muted);margin:10px 0 5px;font-size:11.5px}
.ipop .ir{display:flex;gap:6px}
.ipop input{flex:1;min-width:0;height:32px;border:1px solid var(--line);border-radius:8px;padding:0 9px;background:transparent;color:var(--muted);font-size:11.5px;font-family:inherit}
.ipop .cp{height:32px;padding:0 12px;border-radius:8px;border:0;background:var(--fg);color:var(--bg);font-weight:600;font-size:12px;cursor:pointer;font-family:inherit;flex:none}
.ipop p{margin:9px 0 0;color:var(--muted);line-height:1.55;font-size:11.5px}
.ipop .so{margin-top:8px;padding:0;border:0;background:none;color:var(--accent);font-weight:600;font-size:12px;cursor:pointer;font-family:inherit}
.shd{font-size:11.5px;color:var(--muted);line-height:1.6}
.pill2{height:28px;padding:0 11px;border-radius:14px;border:1px solid var(--line);background:var(--bg);font-size:11.5px;font-weight:600;cursor:pointer}
#toast{position:fixed;top:12px;left:50%;transform:translateX(-50%);padding:7px 14px;border-radius:16px;background:var(--fg);color:var(--bg);font-size:12px;font-weight:600;white-space:nowrap;box-shadow:0 6px 16px rgba(0,0,0,.2);z-index:9}
</style>
</head>
<body data-theme="light">
<div class="rz l" data-hit="10" aria-hidden="true"></div><div class="rz r" data-hit="11" aria-hidden="true"></div>
<div class="rz b" data-hit="15" aria-hidden="true"></div><div class="rz bl" data-hit="16" aria-hidden="true"></div>
<div class="rz br" data-hit="17" title="끌어서 크기 조절" aria-hidden="true"></div>
<div id="card">
  <div id="hd">
    <div class="mon"><b id="mNum">--</b><span id="mName"></span></div>
    <button class="ib" id="prev" aria-label="이전 달" title="이전 달"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M15 6l-6 6 6 6"/></svg></button>
    <button class="ib" id="next" aria-label="다음 달" title="다음 달"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M9 6l6 6-6 6"/></svg></button>
    <span class="sep"></span>
    <button class="ib" id="bOpa" aria-label="투명도" title="투명도"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="12" cy="12" r="9"/><path d="M12 3a9 9 0 0 1 0 18z" fill="currentColor"/></svg></button>
    <button class="ib" id="bPin" aria-label="항상 위에 표시" title="항상 위에 표시"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 17v5M8 3h8l-1 6 3 4H6l3-4z"/></svg></button>
    <button class="ib" id="bMenu" aria-label="설정" title="설정"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"/></svg></button>
    <button class="ib" id="bHide" aria-label="작업 표시줄로 내리기" title="작업 표시줄로 내리기"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><path d="M5 12h14"/></svg></button>
    <button class="ib" id="bTray" aria-label="트레이 아이콘으로 숨기기" title="트레이 아이콘으로 숨기기"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><path d="M6 6l12 12M18 6L6 18"/></svg></button>
  </div>

  <div id="ntBox" role="status" aria-live="polite"></div>
  <div class="upd" id="upd" role="status" hidden><i></i><span id="updText"></span><button type="button" id="updBtn">업데이트</button></div>

  <!-- 팀 휴가 로그인 -->
  <form class="login" id="login" hidden novalidate>
    <h2>팀 휴가 로그인</h2>
    <p>팀 휴가 캘린더 사이트와 같은 아이디·PIN으로 로그인하세요.</p>
    <label for="lId">아이디<input id="lId" autocomplete="username" maxlength="20" placeholder="예: 홍길동" spellcheck="false"></label>
    <label for="lPw">PIN (숫자 4자리)<input id="lPw" type="password" inputmode="numeric" autocomplete="current-password" maxlength="4" placeholder="••••"></label>
    <button class="btn pri" id="lBtn" type="submit">로그인</button>
    <p class="msg" id="lMsg" role="status"></p>
    <button class="link" type="button" id="lSite">처음이거나 PIN을 잊었다면 사이트에서 설정하기</button>
  </form>

  <!-- 달력 -->
  <div id="calWrap" hidden>
    <div class="sh" id="calHd"><span class="t">달력</span><span class="colsum" id="calSum"></span><button class="ch" type="button" id="calCh" aria-expanded="true" aria-label="달력 접기" title="접기 / 펼치기"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M6 9l6 6 6-6"/></svg></button></div>
    <div id="calBody">
    <div class="dow"><div>일</div><div>월</div><div>화</div><div>수</div><div>목</div><div>금</div><div>토</div></div>
    <div class="grid" id="grid"></div>
    <div class="legrow"><div class="leg" id="leg" aria-hidden="true"><span id="legMy"><i class="d" style="--c:var(--accent)"></i>내 일정</span><span><i class="bar"></i>팀원 휴가</span><span id="legOut" hidden><i class="bar out"></i>팀 밖</span><span id="legMe" hidden><i class="bar me"></i>내 휴가</span></div><button class="rf" id="bRefresh" type="button" aria-label="새로고침" title="새로고침 (팀 휴가 + 내 일정)"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M20 11a8 8 0 1 0-2.3 5.7"/><path d="M20 4v7h-7"/></svg><span id="rfTxt"></span></button></div>
    <div id="calChips" class="calchips"></div>
    </div>
  </div>

  <!-- 선택한 날: 내 일정이 먼저, 팀원 휴가는 한 줄 요약 -->
  <section class="sec" id="daySec" hidden>
    <div class="sh">
      <span class="t" id="dayLabel"></span>
      <span style="flex:1"></span>
      <span class="colsum" id="daySum"></span>
      <button class="pill" id="gAddBtn" type="button" hidden><svg viewBox="0 0 24 24" fill="none" stroke-width="2.5" stroke-linecap="round" aria-hidden="true"><path d="M12 5v14M5 12h14"/></svg>일정</button><button class="ch" type="button" id="dayCh" aria-expanded="true" aria-label="오늘 접기" title="접기 / 펼치기"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M6 9l6 6 6-6"/></svg></button>
    </div>
    <div class="dayev" id="dayEvents"></div>
    <div class="abs">
      <button class="absh" id="absToggle" type="button" aria-expanded="false" aria-controls="dayList"><b id="dayCount"></b><span id="absNames"></span></button>
      <button class="lnk" id="addBtn" type="button">+ 휴가</button>
      <button class="tg" id="allBtn" type="button" role="switch" aria-checked="false" title="내 팀원이 아닌 사람의 휴가도 함께 보기" hidden><i aria-hidden="true"></i>전체</button>
      <button class="lnk" id="teamBtn" type="button" title="달력에 휴가를 표시할 팀원 고르기">팀원</button>
    </div>
    <ul class="list" id="dayList" hidden></ul>
    <p class="msg" id="dayMsg" role="status" hidden></p>
  </section>

  <!-- 내 일정 -->
  <section class="sec" id="gSec">
    <div class="sh"><span class="t" id="gHead">내 일정</span><button class="lo" id="gOut" type="button" hidden>로그아웃</button><button class="gp" id="gOpen" type="button" title="브라우저에서 구글 캘린더 열기" aria-label="구글 캘린더 열기"><svg viewBox="0 0 48 48" aria-hidden="true"><path fill="#EA4335" d="M24 9.5c3.5 0 6.6 1.2 9.1 3.6l6.8-6.8C35.8 2.4 30.3 0 24 0 14.6 0 6.6 5.4 2.7 13.3l7.9 6.1C12.5 13.7 17.8 9.5 24 9.5z"/><path fill="#4285F4" d="M46.5 24.5c0-1.6-.1-3.1-.4-4.5H24v9h12.7c-.6 3-2.3 5.5-4.8 7.2l7.7 6c4.5-4.2 6.9-10.3 6.9-17.7z"/><path fill="#FBBC05" d="M10.6 28.6c-.5-1.4-.8-3-.8-4.6s.3-3.2.8-4.6l-7.9-6.1C1 16.6 0 20.2 0 24s1 7.4 2.7 10.7l7.9-6.1z"/><path fill="#34A853" d="M24 48c6.5 0 11.9-2.1 15.9-5.8l-7.7-6c-2.1 1.4-4.9 2.3-8.2 2.3-6.2 0-11.5-4.2-13.4-9.9l-7.9 6.1C6.6 42.6 14.6 48 24 48z"/></svg><span>열기</span><span class="ar" aria-hidden="true">↗</span></button><span class="colsum" id="gSum"></span><button class="ch" type="button" id="gCh" aria-expanded="true" aria-label="내 일정 접기" title="접기 / 펼치기"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M6 9l6 6 6-6"/></svg></button>
      </div>
    <div id="gBody" class="list"></div>
  </section>

  <div class="yr">
    <div id="dlBox" class="dlbox"></div>
    <div id="yrYear" aria-hidden="true"><div class="yb" id="yb"></div><div class="yl"><span id="yl1"></span><span id="yl2"></span></div></div>
  </div>

  <div id="toast" role="status" hidden></div>

  <!-- 휴가 등록 팝업 -->
  <div id="sheet" class="sheet" hidden>
    <form class="dlg" role="dialog" aria-modal="true" aria-labelledby="sTitle" id="sForm" novalidate>
      <span class="grab" aria-hidden="true"></span>
      <div class="dh"><b id="sTitle">휴가 등록</b><button class="x" type="button" id="sClose" aria-label="닫기"><svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" aria-hidden="true"><path d="M6 6l12 12M18 6L6 18"/></svg></button></div>
      <div style="display:flex;flex-direction:column;gap:7px">
        <span style="font-size:11px;font-weight:600;color:var(--muted)" id="typeLbl">구분</span>
        <div class="chips" id="chips" role="radiogroup" aria-labelledby="typeLbl"></div>
      </div>
      <div class="two">
        <label for="sStart">시작일<input type="date" id="sStart"></label>
        <label for="sEnd">종료일<input type="date" id="sEnd"></label>
      </div>
      <label for="sMemo">메모 (선택)<input id="sMemo" maxlength="60" placeholder="예: 가족여행 · 급한 건은 카톡" autocomplete="off"></label>
      <span class="calc" id="sCalc"></span>
      <div class="acts"><button class="btn" type="button" id="sCancel">취소</button><button class="btn pri" type="submit" id="sOk">등록하기</button></div>
    </form>
  </div>

  <!-- 구글 일정 등록 팝업 -->
  <div id="gsheet" class="sheet" hidden>
    <form class="dlg" role="dialog" aria-modal="true" aria-labelledby="gTitleH" id="gForm" novalidate>
      <span class="grab" aria-hidden="true"></span>
      <div class="dh"><b id="gTitleH">일정 추가</b><button class="x" type="button" id="gClose" aria-label="닫기"><svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" aria-hidden="true"><path d="M6 6l12 12M18 6L6 18"/></svg></button></div>
      <label for="gTitle">제목<input id="gTitle" maxlength="200" placeholder="예: 구조 검토 미팅" autocomplete="off"></label>
      <div class="two">
        <label for="gDate">날짜<input type="date" id="gDate"></label>
        <label class="check" for="gAll" style="align-self:end;height:40px"><input type="checkbox" id="gAll">종일</label>
      </div>
      <div class="two" id="gTimes">
        <label for="gStart">시작<input type="time" id="gStart" step="300"></label>
        <label for="gEnd">종료<input type="time" id="gEnd" step="300"></label>
      </div>
      <p class="calc" id="gCalNote" hidden></p>
      <div class="fld" id="gCalFld">
        <span class="flbl" id="gCalLbl">캘린더</span>
        <div class="chips" id="gCals" role="radiogroup" aria-labelledby="gCalLbl"></div>
        <div class="newcal" id="gNew" hidden>
          <label for="gNewName">새 캘린더 이름<input id="gNewName" maxlength="100" placeholder="예: 현장 일정" autocomplete="off"></label>
          <div class="sw" id="gSw" role="radiogroup" aria-label="캘린더 색상"></div>
          <p class="msg" id="gNewMsg" role="status"></p>
          <div class="nact"><button type="button" class="btn sm" id="gNewCancel">취소</button><button type="button" class="btn sm pri" id="gNewOk">만들기</button></div>
        </div>
      </div>
      <label for="gLoc">장소 (선택)<input id="gLoc" maxlength="200" autocomplete="off"></label>
      <label for="gDesc">메모 (선택)<input id="gDesc" maxlength="500" autocomplete="off"></label>
      <span class="calc" id="gCalc" role="status"></span>
      <div class="acts"><button class="btn danger" type="button" id="gDel" hidden>삭제</button><button class="btn" type="button" id="gCancel">취소</button><button class="btn pri" type="submit" id="gOk">추가하기</button></div>
    </form>
  </div>

  <!-- 설정 -->
  <div id="setsheet" class="sheet" hidden>
    <form class="dlg sets" role="dialog" aria-modal="true" aria-labelledby="setTitle" id="setForm" novalidate>
      <span class="grab" aria-hidden="true"></span>
      <div class="dh"><b id="setTitle">설정</b><button class="x" type="button" id="setClose" aria-label="닫기"><svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" aria-hidden="true"><path d="M6 6l12 12M18 6L6 18"/></svg></button></div>
      <div class="stabs" role="tablist" id="setTabs"></div>
      <div id="setBody"></div>
      <div class="sft"><span>바뀐 내용은 바로 적용돼요</span><span id="setVer"></span></div>
    </form>
  </div>

  <!-- 내 팀원 고르기 -->
  <div id="tsheet" class="sheet" hidden>
    <form class="dlg" role="dialog" aria-modal="true" aria-labelledby="tTitle" id="tForm" novalidate>
      <span class="grab" aria-hidden="true"></span>
      <div class="dh"><b id="tTitle">내 팀원</b><button class="x" type="button" id="tClose" aria-label="닫기"><svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" aria-hidden="true"><path d="M6 6l12 12M18 6L6 18"/></svg></button></div>
      <span class="shd">체크한 팀원의 휴가만 달력에 보여요. 내 휴가는 항상 보여요.</span>
      <div class="tact"><button class="lnk" type="button" id="tAll">전체 선택</button><button class="lnk" type="button" id="tNone">전체 해제</button><span id="tCount"></span></div>
      <div class="tlist" id="tList" role="group" aria-label="팀원 목록"></div>
      <div class="acts"><button class="btn" type="button" id="tCancel">취소</button><button class="btn pri" type="submit" id="tOk">완료</button></div>
    </form>
  </div>
</div>

<script>
(() => {
  // ---------------- 설정 (팀 휴가 사이트와 동일) ----------------
  const CFG = {
    URL: "https://otfggkzxspsvxljogwgj.supabase.co",
    KEY: "sb_publishable_hfmN0pqZmUOiwUYEX61NTw_cgnyS78Z",
    SITE: "https://pa-architect.github.io/team-leave/"
  };
  const HOLIDAYS = {
    "2026-01-01":"신정","2026-02-16":"설날 연휴","2026-02-17":"설날","2026-02-18":"설날 연휴","2026-03-01":"삼일절","2026-03-02":"대체공휴일",
    "2026-05-05":"어린이날","2026-05-24":"부처님오신날","2026-05-25":"대체공휴일","2026-06-03":"지방선거","2026-06-06":"현충일",
    "2026-08-15":"광복절","2026-08-17":"대체공휴일","2026-09-24":"추석 연휴","2026-09-25":"추석","2026-09-26":"추석 연휴",
    "2026-10-03":"개천절","2026-10-05":"대체공휴일","2026-10-09":"한글날","2026-12-25":"성탄절",
    "2027-01-01":"신정","2027-02-06":"설날 연휴","2027-02-07":"설날","2027-02-08":"설날 연휴","2027-02-09":"대체공휴일","2027-03-01":"삼일절",
    "2027-05-05":"어린이날","2027-05-13":"부처님오신날","2027-06-06":"현충일","2027-08-15":"광복절","2027-08-16":"대체공휴일",
    "2027-09-14":"추석 연휴","2027-09-15":"추석","2027-09-16":"추석 연휴","2027-10-03":"개천절","2027-10-04":"대체공휴일",
    "2027-10-09":"한글날","2027-10-11":"대체공휴일","2027-12-25":"성탄절","2027-12-27":"대체공휴일"
  };
  const HALF = new Set(["오전반차","오후반차"]);
  const pinPw = pin => `tl-pin-${pin}-calendar`;   // 팀 휴가 사이트와 같은 방식으로 PIN을 비밀번호로 변환
  const TYPES = ["연차","오전반차","오후반차","경조휴가","병가","교육·출장","기타"];
  const PAL = { light:["#2f6fdb","#d2671b","#178a6b","#b0368f","#7656d6","#a07a00","#c23b4a","#2b8fa8"],
                dark: ["#6f9bff","#ff9a52","#3fc6a0","#e56cc4","#a58bff","#e0b33a","#ff6f80","#4fc3df"] };
  const MONTHS = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"];
  const DOW = ["일","월","화","수","목","금","토"];

  const $ = id => document.getElementById(id);
  const pad = n => String(n).padStart(2, "0");
  const ymd = d => `${d.getFullYear()}-${pad(d.getMonth()+1)}-${pad(d.getDate())}`;
  const parse = s => { const [y,m,d] = s.split("-").map(Number); return new Date(y, m-1, d); };
  const isOff = s => { const g = parse(s).getDay(); return g === 0 || g === 6 || !!HOLIDAYS[s]; };
  const esc = s => String(s ?? "").replace(/[&<>"]/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"}[c]));
  function workDays(start, end, type) {
    if (HALF.has(type)) return isOff(start) ? 0 : 0.5;
    let n = 0; for (let d = parse(start); ymd(d) <= end; d.setDate(d.getDate()+1)) if (!isOff(ymd(d))) n++;
    return n;
  }
  function colorIdx(id) { let h = 0; for (const c of String(id)) h = (h*31 + c.charCodeAt(0)) >>> 0; return h % 8; }
  const theme = () => document.body.dataset.theme === "dark" ? "dark" : "light";
  const colorOf = uid => PAL[theme()][colorIdx(uid)];

  // ---------------- 호스트(Windows) 통신 ----------------
  const host = o => { try { window.chrome.webview.postMessage(o); } catch (e) {} };
  const POPUP = new URLSearchParams(location.search).get("popup");   // "leave" | "gevent" | null (위젯 본체)
  const inHost = !!(window.chrome && window.chrome.webview);

  // ---------------- 상태 ----------------
  let sb = null, me = null, members = {}, leaves = [], loaded = false;
  let today = ymd(new Date());
  let view = new Date(); view.setDate(1);
  let selected = today;
  let gmode = "", gEvents = null, gError = "", gStatus = "", gRetried = false;
  let gToken = null, gWritable = [], gCals = [], gAllCalIds = new Set(), tcCfg = null, gAutoLogin = true, gLoaded = null, icsText = null;
  // 불러올 기간: 보고 있는 달 전체 + 오늘부터 2주
  function gWin() {
    const t0 = new Date(); t0.setHours(0, 0, 0, 0);
    const t14 = new Date(t0); t14.setDate(t14.getDate() + 15);
    const vs = new Date(view.getFullYear(), view.getMonth(), 1); vs.setDate(1 - vs.getDay());
    const ve = new Date(view.getFullYear(), view.getMonth() + 1, 1); ve.setDate(ve.getDate() + 7);
    return { from: vs < t0 ? vs : t0, to: ve > t14 ? ve : t14 };
  }
  // 완료 체크 (위젯에만 저장)
  let doneMap = {}; try { doneMap = JSON.parse(localStorage.getItem("tlw.done") || "{}") || {}; } catch (e) {}
  const doneKey = ev => (ev.cal || "ical") + "|" + (ev.id || ev.title) + "|" + ev.s.getTime();
  function saveDone() {
    const cut = Date.now() - 45 * 864e5;               // 45일 지난 기록은 정리
    for (const k in doneMap) if (+k.split("|").pop() < cut) delete doneMap[k];
    try { localStorage.setItem("tlw.done", JSON.stringify(doneMap)); } catch (e) {}
  }
  // 위젯에서 숨긴 캘린더 (구글 설정은 바꾸지 않음)
  let calPref = {}; try { calPref = JSON.parse(localStorage.getItem("tlw.calPref") || "{}") || {}; } catch (e) {}
  const calOn = c => (c.id in calPref) ? !!calPref[c.id] : c.selected !== false;

  // ======================= 팀 휴가 (Supabase) =======================
  function initSupabase() {
    if (!window.supabase) { showLogin("팀 휴가 서버에 연결하지 못했어요. 인터넷 연결을 확인해 주세요."); return; }
    sb = window.supabase.createClient(CFG.URL, CFG.KEY, { auth: { persistSession: true, autoRefreshToken: true, storageKey: "team-leave-auth" } });
    sb.auth.onAuthStateChange((ev, s) => {
      const u = s && s.user || null;
      if (u && (!me || me.id !== u.id)) { me = u; startApp(); }
      if (!u && ev === "SIGNED_OUT") { me = null; showLogin(); }
    });
    sb.auth.getSession().then(({ data }) => {
      if (data.session && data.session.user) { me = data.session.user; startApp(); } else showLogin();
    }).catch(() => showLogin());
  }
  function showLogin(text) {
    $("login").hidden = false; $("calWrap").hidden = true; $("daySec").hidden = true;
    msg($("lMsg"), text || "", text ? "err" : "");
    renderHeader(); report();
  }
  let liveOn = false;
  async function startApp() {
    $("login").hidden = true; $("calWrap").hidden = false; $("daySec").hidden = false;
    await reload();
    if (!liveOn) {
      liveOn = true;
      let t; const fire = () => { clearTimeout(t); t = setTimeout(reload, 300); };
      try {
        sb.channel("team-leave-widget")
          .on("postgres_changes", { event: "*", schema: "public", table: "leaves" }, fire)
          .on("postgres_changes", { event: "*", schema: "public", table: "members" }, fire)
          .subscribe();
      } catch (e) {}
      setInterval(reload, 5 * 60 * 1000);
    }
  }
  async function reload() {
    if (!sb || !me) return;
    try {
      const since = `${new Date().getFullYear()-1}-01-01`;
      const [m, l] = await Promise.all([
        sb.from("members").select("id,display_name"),
        sb.from("leaves").select("id,user_id,type,start_date,end_date,memo").gte("end_date", since).order("start_date")
      ]);
      if (m.error) throw m.error; if (l.error) throw l.error;
      members = {}; for (const r of m.data) members[r.id] = r.display_name || "";
      leaves = l.data; loaded = true;
      renderAll();
    } catch (e) {
      const code = e && (e.code || e.status);
      if (code === 401 || code === "PGRST301") { await sb.auth.signOut(); return; }
      showDayMsg("일정을 불러오지 못했어요. 잠시 후 자동으로 다시 시도해요.", "err");
    }
  }
  $("login").addEventListener("submit", async ev => {
    ev.preventDefault();
    const id = $("lId").value.trim(), pw = $("lPw").value.trim();
    if (!id || !/^\d{4}$/.test(pw)) return msg($("lMsg"), "아이디와 숫자 4자리 PIN을 입력하세요.", "err");
    if (!sb) return msg($("lMsg"), "서버에 연결하지 못했어요.", "err");
    $("lBtn").disabled = true; msg($("lMsg"), "로그인 중…");
    try {
      const { data: email, error: e1 } = await sb.rpc("login_email", { p_login: id });
      if (e1 || !email) { msg($("lMsg"), e1 ? "로그인하지 못했어요. 잠시 후 다시 시도해 주세요." : "아이디 또는 PIN이 맞지 않아요.", "err"); return; }
      const { error } = await sb.auth.signInWithPassword({ email, password: pinPw(pw) });
      if (error) {
        const rate = error.status === 429 || (error.message || "").toLowerCase().includes("rate");
        msg($("lMsg"), rate ? "시도가 너무 많아요. 잠시 후 다시 시도해 주세요." : "아이디 또는 PIN이 맞지 않아요.", "err");
        return;
      }
      $("lPw").value = ""; msg($("lMsg"), "");
    } finally { $("lBtn").disabled = false; }
  });
  $("lSite").onclick = () => host({ cmd: "open", url: CFG.SITE });

  // ---------------- 렌더링 ----------------
  // 내 팀원 (null = 전체)
  let teamSel = null; try { const t = JSON.parse(localStorage.getItem("tlw.team") || "null"); if (Array.isArray(t)) teamSel = t; } catch (e) {}
  let showAll = false; try { showAll = localStorage.getItem("tlw.showAll") === "1"; } catch (e) {}
  const inTeam = uid => showAll || !Array.isArray(teamSel) || teamSel.includes(uid) || (me && uid === me.id);
  const isMyTeam = uid => !Array.isArray(teamSel) || teamSel.includes(uid) || (me && uid === me.id);
  const entries = () => leaves.filter(r => inTeam(r.user_id)).map(r => ({ id: r.id, uid: r.user_id, type: r.type, start: r.start_date, end: r.end_date, memo: r.memo || "", who: members[r.user_id] || "이름 미설정" }));
  const onDay = (list, s) => list.filter(e => e.start <= s && s <= e.end && (!isOff(s) || e.start === e.end));

  // 내 일정 (구글/iCal) 중 표시 중인 캘린더의 일정
  function visibleEvents() {
    if (!gEvents) return [];
    const off = new Set(gCals.filter(c => !calOn(c)).map(c => c.id));
    return gEvents.filter(ev => !(ev.cal && off.has(ev.cal)));
  }
  function eventsOn(dayStr, list) {
    const ds = parse(dayStr), de = new Date(ds); de.setDate(de.getDate() + 1);
    return (list || visibleEvents()).filter(ev => ev.s < de && (ev.e > ds || (ev.e - ev.s === 0 && ev.s >= ds)))
      .sort((a, b) => (b.all - a.all) || (a.s - b.s));
  }
  function evRow(ev, dayStart) {
    const now = new Date();
    const tm = ev.all ? "종일" : (dayStart && ev.s < dayStart ? "~" + hhmm(ev.e) : hhmm(ev.s));
    const past = !ev.all && ev.e < now ? " past" : "";
    const key = doneKey(ev), isDone = !!doneMap[key], idx = gEvents.indexOf(ev);
    const canDel = gmode === "google" && ev.id && gWritable.some(c => c.id === ev.cal);
    const canEdit = canDel;
    return `<div class="ev${past}${isDone ? " done" : ""}${canEdit ? " edit" : ""}"${canEdit ? ` data-ev="${idx}" tabindex="0" title="더블클릭해서 수정"` : ""}><button type="button" class="ck" role="checkbox" aria-checked="${isDone}" aria-label="${esc(ev.title)} 완료" data-done="${idx}" style="--c:${esc(ev.color || "var(--accent)")}"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg></button><span class="tm">${tm}</span><span class="ti" title="${esc(ev.title)}">${esc(ev.title)}</span>${canDel ? `<button type="button" class="evx" data-del="${idx}" aria-label="${esc(ev.title)} 삭제" title="삭제">×</button>` : ""}</div>`;
  }
  function bindEvRows(box) {
    box.querySelectorAll(".ev[data-ev]").forEach(r => {
      r.ondblclick = e => { if (e.target.closest("button")) return; const ev = gEvents[+r.dataset.ev]; if (ev) openEdit(ev); };
      r.onkeydown = e => { if (e.key === "Enter" && e.target === r) { const ev = gEvents[+r.dataset.ev]; if (ev) openEdit(ev); } };
    });
    box.querySelectorAll("[data-done]").forEach(b => b.onclick = () => {
      const ev = gEvents[+b.dataset.done]; if (!ev) return;
      const k = doneKey(ev);
      if (doneMap[k]) delete doneMap[k]; else doneMap[k] = 1;
      saveDone(); renderAll();
      const nb = box.querySelector(`[data-done="${b.dataset.done}"]`); if (nb) nb.focus();
    });
    box.querySelectorAll("[data-del]").forEach(b => b.onclick = async () => {
      const ev = gEvents[+b.dataset.del]; if (!ev) return;
      if (!b.classList.contains("arm")) {
        b.classList.add("arm"); b.textContent = "삭제?"; b.setAttribute("aria-label", `${ev.title} 삭제 확인`);
        setTimeout(() => { if (b.isConnected) { b.classList.remove("arm"); b.textContent = "×"; } }, 3000);
        return;
      }
      b.disabled = true;
      try {
        if (!gToken) throw new Error("token");
        const r = await fetch(`https://www.googleapis.com/calendar/v3/calendars/${encodeURIComponent(ev.cal)}/events/${encodeURIComponent(ev.id)}`, { method: "DELETE", headers: { Authorization: "Bearer " + gToken } });
        if (r.status === 401) { host({ cmd: "gtoken", force: true }); toast("다시 연결했어요. 한 번 더 눌러 주세요."); b.disabled = false; return; }
        if (r.status === 403) { toast("이 일정을 삭제할 권한이 없어요"); b.disabled = false; return; }
        if (!r.ok && r.status !== 410 && r.status !== 404) throw new Error("HTTP " + r.status);
        selfMark(ev.cal, ev.id);
        gEvents = gEvents.filter(x => x !== ev);
        delete doneMap[doneKey(ev)]; saveDone();
        toast(`'${ev.title}' 일정을 삭제했어요`); renderAll();
      } catch (e) { toast("일정을 삭제하지 못했어요"); b.disabled = false; }
    });
  }

  function renderHeader() {
    $("mNum").textContent = view.getMonth() + 1;
    $("mName").textContent = `${MONTHS[view.getMonth()]} ${view.getFullYear()}`;
    const now = new Date(), y = now.getFullYear();
    const start = new Date(y, 0, 1), total = Math.round((new Date(y + 1, 0, 1) - start) / 864e5);
    const dayNo = Math.floor((new Date(y, now.getMonth(), now.getDate()) - start) / 864e5) + 1;
    const yb = $("yb"); yb.replaceChildren();
    for (let m = 0; m < 12; m++) { const s = document.createElement("span"); if (m < now.getMonth()) s.className = "done"; if (m === now.getMonth()) s.className = "now"; yb.append(s); }
    $("yl1").textContent = `${y} · ${dayNo}일째`;
    $("yl2").textContent = `남은 ${total - dayNo}일`;
    renderDeadlines();
  }
  function renderGrid() {
    const list = entries(), evs = visibleEvents();
    const y = view.getFullYear(), m = view.getMonth();
    const first = new Date(y, m, 1), start = new Date(first); start.setDate(1 - first.getDay());
    const weeks = Math.ceil((first.getDay() + new Date(y, m + 1, 0).getDate()) / 7);
    const grid = $("grid"); grid.replaceChildren();
    const cellW = (grid.clientWidth || $("card").clientWidth - 36) / 7;
    const wide = cellW >= 70, perCell = cellW >= 85 ? 3 : 2;
    grid.classList.toggle("wide", wide); lastWide = wide;
    $("legMy").hidden = !gEvents;
    $("legOut").hidden = !(showAll && Array.isArray(teamSel));
    $("legMe").hidden = !(me && leaves.some(l => l.user_id === me.id));
    for (let i = 0; i < weeks * 7; i++) {
      const d = new Date(start); d.setDate(start.getDate() + i); const s = ymd(d);
      const b = document.createElement("button"); b.type = "button"; b.className = "cell";
      if (d.getMonth() !== m) { b.classList.add("out"); b.tabIndex = -1; b.setAttribute("aria-hidden", "true"); grid.append(b); continue; }
      if (d.getDay() === 0 || HOLIDAYS[s]) b.classList.add("red"); else if (d.getDay() === 6) b.classList.add("sat");
      if (s === today) b.classList.add("today");
      if (s === selected) b.classList.add("sel");
      const mine = eventsOn(s, evs);
      if (mine.length) b.classList.add("has");
      const n = document.createElement("span"); n.className = "n"; n.textContent = d.getDate();
      // 내 일정: 캘린더 색 점 (최대 3개)
      const dots = document.createElement("span"); dots.className = "dots";
      if (wide) {
        dots.className = "evs";
        const show = mine.length > perCell ? perCell - 1 : perCell;
        for (const ev of mine.slice(0, show)) {
          const c = document.createElement("span"); c.className = "ec" + (doneMap[doneKey(ev)] ? " dn" : "");
          c.style.setProperty("--c", ev.color || "var(--accent)");
          c.textContent = (ev.all || (ev.s < d) ? "" : hhmm(ev.s) + " ") + ev.title; c.title = ev.title;
          if (gmode === "google" && ev.id && gWritable.some(w => w.id === ev.cal)) { c.title = ev.title + " (더블클릭해서 수정)"; c.ondblclick = e2 => { e2.stopPropagation(); openEdit(ev); }; }
          dots.append(c);
        }
        if (mine.length > show) { const mo = document.createElement("span"); mo.className = "ec more"; mo.textContent = `+${mine.length - show}개`; dots.append(mo); }
      } else if (mine.length) {
        for (const ev of mine.slice(0, 3)) { const x = document.createElement("span"); x.className = "d"; x.style.setProperty("--c", ev.color || "var(--accent)"); dots.append(x); }
        if (mine.length > 3) { const mo = document.createElement("span"); mo.className = "more"; mo.textContent = "+" + (mine.length - 3); dots.append(mo); }
      } else {
        const x = document.createElement("span"); x.className = "d e" + (s < today ? " past" : ""); dots.append(x);
      }
      // 팀원 휴가: 흐린 막대 (내 휴가는 주황)
      const es = onDay(list, s);
      const tb = document.createElement("span"); tb.className = "tb";
      const mineLeave = me && es.some(e => e.uid === me.id);
      if (mineLeave) { const x = document.createElement("i"); x.className = "me"; tb.append(x); }
      const rest = es.filter(e => !me || e.uid !== me.id).sort((a, b) => isMyTeam(b.uid) - isMyTeam(a.uid));
      for (const e of rest.slice(0, mineLeave ? 1 : 2)) { const x = document.createElement("i"); if (!isMyTeam(e.uid)) x.className = "out"; tb.append(x); }
      b.append(n, dots, tb);
      b.setAttribute("aria-label", `${d.getMonth()+1}월 ${d.getDate()}일${HOLIDAYS[s] ? " " + HOLIDAYS[s] : ""}${mine.length ? ", 내 일정 " + mine.length + "개" : ""}${es.length ? ", 휴가 " + es.length + "명" : ""}`);
      if (s === selected) b.setAttribute("aria-pressed", "true");
      b.onclick = () => {
        const now2 = Date.now(), dbl = cellClick.s === s && now2 - cellClick.t < 450;
        cellClick = dbl ? { s: "", t: 0 } : { s, t: now2 };
        selected = s; renderGrid(); renderDay(); renderG();
        if (dbl) addOnDay();      // 같은 날짜를 두 번 빠르게 누르면 일정 추가
      };
      grid.append(b);
    }
  }
  let cellClick = { s: "", t: 0 };
  function addOnDay() {
    if (gmode === "google" && gWritable.length) openGSheet(null);
    else toast(gmode === "google" ? "구글 캘린더를 불러오는 중이에요. 잠시 후 다시 해 주세요." : "구글 캘린더를 연결하면 더블클릭으로 일정을 추가할 수 있어요");
  }
  function renderDay() {
    const d = parse(selected);
    $("dayLabel").textContent = `${d.getMonth()+1}.${d.getDate()} ${DOW[d.getDay()]}${selected === today ? " · 오늘" : ""}${HOLIDAYS[selected] ? " · " + HOLIDAYS[selected] : ""}`;
    // 그날 내 일정
    const de = $("dayEvents");
    if (gEvents) {
      const mine = eventsOn(selected);
      de.innerHTML = mine.length ? mine.map(ev => evRow(ev, parse(selected))).join("") : `<p class="empty" style="margin:0">이 날은 일정이 없어요.</p>`;
      bindEvRows(de);
    } else de.innerHTML = "";
    de.hidden = !gEvents;
    // 팀원 휴가 요약 한 줄
    const es = onDay(entries(), selected).sort((a, b) => (me && a.uid === me.id ? -1 : 0) - (me && b.uid === me.id ? -1 : 0) || a.who.localeCompare(b.who, "ko"));
    $("dayCount").textContent = !loaded ? "불러오는 중…" : (es.length ? `부재 ${es.length}` : (isOff(selected) ? "휴일" : "부재 없음"));
    // 내 팀이 먼저, 팀 밖 사람은 뒤에 괄호로
    const mineT = es.filter(e => isMyTeam(e.uid)), others = es.filter(e => !isMyTeam(e.uid));
    $("absNames").textContent = mineT.map(e => `${me && e.uid === me.id ? "나" : e.who} ${e.type}`).join(" · ")
      + (others.length ? `${mineT.length ? " · " : ""}(팀 밖 ${others.map(e => e.who).join(", ")})` : "");
    $("allBtn").hidden = !Array.isArray(teamSel);
    $("allBtn").setAttribute("aria-checked", showAll ? "true" : "false");
    $("absToggle").disabled = !es.length;
    if (!es.length) { $("dayList").hidden = true; $("absToggle").setAttribute("aria-expanded", "false"); }
    const ul = $("dayList"); ul.replaceChildren();
    if (!loaded) { const li = document.createElement("li"); li.className = "empty"; li.textContent = "불러오는 중…"; ul.append(li); return; }
    if (!es.length) { const li = document.createElement("li"); li.className = "empty"; li.textContent = isOff(selected) ? "휴일" : "모두 출근"; ul.append(li); return; }
    for (const e of es) {
      const li = document.createElement("li"); li.className = "row";
      const dot = document.createElement("span"); dot.className = "d" + (HALF.has(e.type) ? " h" : ""); dot.style.setProperty("--c", colorOf(e.uid));
      const nm = document.createElement("span"); nm.className = "nm"; nm.textContent = e.who + (me && e.uid === me.id ? " (나)" : "");
      const memo = document.createElement("span"); memo.className = "memo"; memo.textContent = e.memo; memo.title = e.memo;
      const ty = document.createElement("span"); ty.className = "ty"; ty.textContent = e.type + (e.start !== e.end ? ` · ${fmtShort(e.start)}~${fmtShort(e.end)}` : "");
      li.append(dot, nm, memo, ty);
      if (me && e.uid === me.id) {
        const del = document.createElement("button"); del.type = "button"; del.className = "del"; del.textContent = "삭제";
        del.setAttribute("aria-label", `${e.type} ${fmtShort(e.start)} 삭제`);
        del.onclick = async () => {
          if (!del.classList.contains("arm")) { del.classList.add("arm"); del.textContent = "삭제 확인"; setTimeout(() => { del.classList.remove("arm"); del.textContent = "삭제"; }, 3000); return; }
          del.disabled = true;
          try {
            const { data, error } = await sb.from("leaves").delete().eq("id", e.id).select("id");
            if (error) throw error;
            toast((data || []).length ? "삭제했어요" : "삭제할 권한이 없어요");
            await reload();
          } catch { toast("삭제하지 못했어요"); del.disabled = false; }
        };
        li.append(del);
      }
      ul.append(li);
    }
  }
  $("absToggle").onclick = () => {
    const open = $("dayList").hidden;
    $("dayList").hidden = !open; $("absToggle").setAttribute("aria-expanded", open ? "true" : "false"); report();
  };
  const fmtShort = s => { const d = parse(s); return `${d.getMonth()+1}/${d.getDate()}`; };
  function showDayMsg(t, kind) { const p = $("dayMsg"); p.hidden = !t; msg(p, t, kind); report(); }
  function msg(el, t, kind) { el.textContent = t || ""; el.className = "msg" + (kind ? " " + kind : ""); }
  let toastT;
  function toast(t) { const el = $("toast"); el.textContent = t; el.hidden = false; clearTimeout(toastT); toastT = setTimeout(() => el.hidden = true, 2200); }
  // ---- 구역 접기 (달력 · 오늘 · 내 일정) ----
  let upCount = 0;
  let colSt = {}; try { colSt = JSON.parse(localStorage.getItem("tlw.col") || "{}") || {}; } catch (e) {}
  const COLS = { cal: ["calWrap", "calCh"], day: ["daySec", "dayCh"], g: ["gSec", "gCh"] };
  function applyCol() {
    for (const [k, [sec, btn]] of Object.entries(COLS)) {
      const on = !!colSt[k];
      $(sec).classList.toggle("col", on); $(btn).setAttribute("aria-expanded", on ? "false" : "true");
    }
    colSums();
  }
  function colSums() {
    const vs = new Date(view.getFullYear(), view.getMonth(), 1), ve = new Date(view.getFullYear(), view.getMonth() + 1, 1);
    const evM = visibleEvents().filter(ev => ev.s < ve && ev.e > vs).length;
    const vsS = ymd(vs), veS = ymd(new Date(ve.getTime() - 864e5));
    const lvM = me ? entries().filter(l => l.start <= veS && l.end >= vsS).length : 0;
    $("calSum").textContent = colSt.cal ? `${view.getMonth() + 1}월 일정 ${evM}${me ? ` · 휴가 ${lvM}` : ""}` : "";
    const evD = visibleEvents().length ? eventsOn(selected).length : 0;
    const lvD = me ? entries().filter(l => l.start <= selected && l.end >= selected).length : 0;
    $("daySum").textContent = colSt.day ? `일정 ${evD}${me ? ` · 휴가 ${lvD}` : ""}` : "";
    $("gSum").textContent = colSt.g && gEvents ? `다가오는 ${upCount}개` : "";
  }
  for (const [k, [sec, btn]] of Object.entries(COLS)) {
    $(btn).onclick = () => {
      colSt[k] = !colSt[k];
      try { localStorage.setItem("tlw.col", JSON.stringify(colSt)); } catch (e) {}
      applyCol(); lastH = 0; report();
    };
  }
  function renderAll() { renderHeader(); if (me) { renderGrid(); renderDay(); } renderG(); applyCol(); report(); }
  function monthChanged() {
    renderAll();
    if (gmode === "google" && gLoaded) { const w = gWin(); if (w.from < gLoaded.from || w.to > gLoaded.to) gRequest(); }
    else if (gmode === "ical" && icsText) loadIcs(icsText);
  }
  $("prev").onclick = () => { view.setMonth(view.getMonth() - 1); monthChanged(); };
  $("next").onclick = () => { view.setMonth(view.getMonth() + 1); monthChanged(); };
  $("mNum").parentElement.ondblclick = () => { view = new Date(); view.setDate(1); selected = today; renderAll(); };

  // ---------------- 휴가 등록 팝업 ----------------
  let sType = "연차";
  function renderChips() {
    const c = $("chips"); c.replaceChildren();
    for (const t of TYPES) {
      const b = document.createElement("button"); b.type = "button"; b.className = "chip" + (t === sType ? " on" : "");
      b.textContent = t; b.setAttribute("role", "radio"); b.setAttribute("aria-checked", t === sType ? "true" : "false");
      b.onclick = () => { sType = t; if (HALF.has(t)) $("sEnd").value = $("sStart").value; renderChips(); calc(); };
      c.append(b);
    }
    $("sEnd").disabled = HALF.has(sType);
  }
  function calc() {
    const s = $("sStart").value, e = HALF.has(sType) ? s : $("sEnd").value, out = $("sCalc");
    let t = "", bad = false;
    if (!s || !e) { t = "시작일과 종료일을 선택하세요."; bad = true; }
    else if (e < s) { t = "종료일이 시작일보다 빨라요."; bad = true; }
    else if (me && leaves.some(l => l.user_id === me.id && l.start_date <= e && s <= l.end_date)) { t = "이미 등록한 휴가와 날짜가 겹쳐요."; bad = true; }
    else { const n = workDays(s, e, sType); t = `차감 기준 ${n}일 (주말·공휴일 제외)`; }
    out.textContent = t; out.className = "calc" + (bad ? " err" : "");
    $("sOk").disabled = bad;
    return !bad;
  }
  function openSheet() {
    if (!me) return;
    if (inHost && !POPUP) {
      host({ cmd: "popup", kind: "leave", data: { date: selected, uid: me.id,
        mine: leaves.filter(l => l.user_id === me.id).map(l => ({ user_id: l.user_id, start_date: l.start_date, end_date: l.end_date })) } });
      return;
    }
    sType = "연차"; $("sStart").value = selected; $("sEnd").value = selected; $("sMemo").value = "";
    renderChips(); calc();
    $("sheet").hidden = false; report();
    setTimeout(() => $("chips").firstChild && $("chips").firstChild.focus(), 30);
  }
  function closeSheet() { if (POPUP) { host({ cmd: "close" }); return; } $("sheet").hidden = true; report(); $("addBtn").focus(); }
  $("addBtn").onclick = openSheet;
  $("sClose").onclick = closeSheet; $("sCancel").onclick = closeSheet;
  $("sheet").addEventListener("click", e => { if (e.target === $("sheet")) closeSheet(); });
  document.addEventListener("keydown", e => { if (e.key === "Escape" && !$("sheet").hidden) closeSheet(); });
  $("sStart").addEventListener("change", () => { const s = $("sStart").value; if (HALF.has(sType) || !$("sEnd").value || $("sEnd").value < s) $("sEnd").value = s; calc(); });
  $("sEnd").addEventListener("change", calc);
  $("sForm").addEventListener("submit", async ev => {
    ev.preventDefault();
    if (!calc()) return;
    const start = $("sStart").value, end = HALF.has(sType) ? start : $("sEnd").value, memo = $("sMemo").value.trim();
    $("sOk").disabled = true; $("sOk").textContent = "저장 중…";
    try {
      const { error } = await sb.from("leaves").insert({ type: sType, start_date: start, end_date: end, memo: memo || null });
      if (error) throw error;
      const doneMsg = `${fmtShort(start)}${start !== end ? "~" + fmtShort(end) : ""} ${sType} 등록했어요`;
      if (POPUP) { host({ cmd: "done", msg: doneMsg, date: start }); return; }
      closeSheet(); toast(doneMsg);
      selected = start; const sd = parse(start); view = new Date(sd.getFullYear(), sd.getMonth(), 1);
      await reload();
    } catch (e) {
      const out = $("sCalc"); out.textContent = "저장하지 못했어요. 다시 로그인한 뒤 시도해 주세요."; out.className = "calc err";
    } finally { $("sOk").disabled = false; $("sOk").textContent = "등록하기"; }
  });

  // ======================= 내 일정 (구글 / iCal) =======================
  let gLastReq = 0, rfAt = 0, rfBusy = false, rfT = null;
  function rfLabel() {
    const el = $("rfTxt"); if (!el) return;
    if (rfBusy) { el.textContent = ""; return; }
    if (!rfAt) { el.textContent = ""; return; }
    const m = Math.floor((Date.now() - rfAt) / 60000);
    el.textContent = m < 1 ? "방금" : m < 60 ? `${m}분 전` : `${Math.floor(m / 60)}시간 전`;
  }
  function rfDone() {
    rfAt = Date.now();
    if (rfBusy) { clearTimeout(rfT); rfT = setTimeout(() => { rfBusy = false; $("bRefresh").classList.remove("spin"); rfLabel(); }, 500); }
    else rfLabel();
  }
  function manualRefresh() {
    if (rfBusy) return;
    rfBusy = true; $("bRefresh").classList.add("spin"); rfLabel();
    try { reload(); } catch (e) {}
    dlAt = 0; if (gmode) gRequest(); else rfDone();
    clearTimeout(rfT); rfT = setTimeout(() => { if (rfBusy) { rfBusy = false; $("bRefresh").classList.remove("spin"); rfAt = Date.now(); rfLabel(); } }, 8000);
  }
  function gRequest() {
    gLastReq = Date.now();
    gError = "";
    if (gmode === "google") host({ cmd: "gtoken" });
    else if (gmode === "ical") host({ cmd: "ics" });
    renderG();
  }
  async function gfetch(url, token) {
    const r = await fetch(url, { headers: { Authorization: "Bearer " + token } });
    if (r.status === 401) { const e = new Error("auth"); e.auth = true; throw e; }
    if (!r.ok) throw new Error("HTTP " + r.status);
    return r.json();
  }
  async function loadGoogle(token) {
    const win = gWin(), t0 = win.from, t1 = win.to;
    const cl = await gfetch("https://www.googleapis.com/calendar/v3/users/me/calendarList?minAccessRole=reader&maxResults=100", token);
    const cals = (cl.items || []).filter(c => !c.hidden);
    gAllCalIds = new Set((cl.items || []).map(c => c.id));
    const isMine = c => c.primary || c.accessRole === "owner";
    gCals = cals.slice().sort((a, b) => (b.primary ? 2 : isMine(b) ? 1 : 0) - (a.primary ? 2 : isMine(a) ? 1 : 0))
      .map(c => ({ id: c.id, color: c.backgroundColor, selected: c.selected, primary: !!c.primary,
        name: c.primary && /@/.test(c.summaryOverride || c.summary || "@") ? "내 캘린더" : (c.summaryOverride || c.summary || c.id) }));
    // 팀 그룹 캘린더: 내 목록에 없어도 그룹 권한으로 읽을 수 있으면 보여준다
    const tIds = new Set(tcCfg ? tcCfg.cals.map(c => c.id) : []);
    for (const c of gCals) if (tIds.has(c.id)) c.team = true;
    const extra = tcCfg ? tcCfg.cals.filter(c => !gAllCalIds.has(c.id)).map(c => ({ id: c.id, color: c.color || "#2f6fdb", selected: true, name: c.name || "팀 캘린더", team: true, extra: true })) : [];
    gWritable = (cl.items || []).filter(c => c.accessRole === "owner" || c.accessRole === "writer")
      .sort((a, b) => (b.primary ? 1 : 0) - (a.primary ? 1 : 0))
      .map(c => { const n = c.summaryOverride || c.summary || ""; return { id: c.id, color: c.backgroundColor,
        name: c.primary ? ((!n || /@/.test(n)) ? "내 캘린더" : n) + " (기본)" : (n || c.id) }; });
    const okExtra = new Set();
    const lists = await Promise.all(cals.concat(extra.map(c => ({ id: c.id, backgroundColor: c.color, extra: true }))).map(c =>
      gfetch(`https://www.googleapis.com/calendar/v3/calendars/${encodeURIComponent(c.id)}/events?singleEvents=true&orderBy=startTime&maxResults=250&timeMin=${encodeURIComponent(t0.toISOString())}&timeMax=${encodeURIComponent(t1.toISOString())}`, token)
        .then(r => { if (c.extra) okExtra.add(c.id); return (r.items || []).map(e => ({ e, color: c.backgroundColor, cal: c.id })); })
        .catch(err => { if (err.auth) throw err; return []; })));   // 그룹에 아직 가입 안 했으면 조용히 건너뜀
    gCals = gCals.concat(extra.filter(c => okExtra.has(c.id)));
    const out = [];
    for (const { e, color, cal } of lists.flat()) {
      if (e.status === "cancelled") continue;
      if ((e.attendees || []).some(a => a.self && a.responseStatus === "declined")) continue;
      const all = !e.start.dateTime;
      const s = all ? parse(e.start.date) : new Date(e.start.dateTime);
      const en = all ? parse(e.end.date) : new Date(e.end.dateTime || e.start.dateTime);
      out.push({ s, e: en, all, title: e.summary || "(제목 없음)", color, cal, id: e.id,
        loc: e.location || "", desc: e.description || "", url: (e.source && e.source.url) || "" });
    }
    gEvents = out; gLoaded = win; gError = ""; gRetried = false;
    try { watchChanges(out, (cl.items || []).find(c => c.primary)); } catch (e) {}
    loadDeadlines(false);
    renderAll(); rfDone();
  }
  function onToken(m) {
    if (m.token) {
      gToken = m.token;
      if (gPendingSave) { const f = gPendingSave; gPendingSave = null; f(); }
      loadGoogle(m.token).catch(err => {
        if (err.auth && !gRetried) { gRetried = true; host({ cmd: "gtoken", force: true }); return; }
        gError = "구글 일정을 불러오지 못했어요."; renderG();
      });
    } else if (m.need === "client") { gEvents = null; gError = ""; gStatus = "client"; renderG(); }
    else if (m.need === "login") { gEvents = null; gError = ""; gStatus = "login"; renderG(); }
    else { gError = m.error || "구글 일정을 불러오지 못했어요."; renderG(); }
  }

  // --- iCal 파서 (반복 일정 포함) ---
  function zoned(y, mo, d, h, mi, s, tz) {
    const guess = Date.UTC(y, mo - 1, d, h, mi, s);
    try {
      const f = new Intl.DateTimeFormat("en-US", { timeZone: tz, hourCycle: "h23", year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", second: "2-digit" });
      const p = {}; f.formatToParts(new Date(guess)).forEach(x => p[x.type] = x.value);
      return new Date(guess - (Date.UTC(+p.year, +p.month - 1, +p.day, +p.hour, +p.minute, +p.second) - guess));
    } catch (e) { return new Date(y, mo - 1, d, h, mi, s); }
  }
  function pdate(v, p) {
    if (!v) return null; v = v.trim(); p = p || {};
    let m = v.match(/^(\d{4})(\d{2})(\d{2})$/);
    if (m || p.VALUE === "DATE") { m = m || v.match(/^(\d{4})(\d{2})(\d{2})/); return { d: new Date(+m[1], m[2] - 1, +m[3]), all: true }; }
    m = v.match(/^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})(Z?)/); if (!m) return null;
    const a = m.slice(1, 7).map(Number);
    if (m[7]) return { d: new Date(Date.UTC(a[0], a[1] - 1, a[2], a[3], a[4], a[5])), all: false };
    if (p.TZID) return { d: zoned(a[0], a[1], a[2], a[3], a[4], a[5], p.TZID.replace(/^"|"$/g, "")), all: false };
    return { d: new Date(a[0], a[1] - 1, a[2], a[3], a[4], a[5]), all: false };
  }
  function pdur(s) {
    const m = /P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?/.exec(s || ""); if (!m) return 0;
    return ((+m[1] || 0) * 604800 + (+m[2] || 0) * 86400 + (+m[3] || 0) * 3600 + (+m[4] || 0) * 60 + (+m[5] || 0)) * 1000;
  }
  function icsParse(text) {
    const lines = text.replace(/\r?\n[ \t]/g, "").split(/\r?\n/), evs = []; let cur = null;
    const unesc = s => s.replace(/\\n/gi, " ").replace(/\\([,;\\])/g, "$1");
    for (const ln of lines) {
      if (ln === "BEGIN:VEVENT") { cur = { ex: [] }; continue; }
      if (ln === "END:VEVENT") { if (cur) evs.push(cur); cur = null; continue; }
      if (!cur) continue;
      const i = ln.indexOf(":"); if (i < 0) continue;
      const parts = ln.slice(0, i).split(";"), val = ln.slice(i + 1), name = parts[0].toUpperCase(), p = {};
      for (const x of parts.slice(1)) { const j = x.indexOf("="); if (j > 0) p[x.slice(0, j).toUpperCase()] = x.slice(j + 1); }
      if (name === "DTSTART") cur.start = pdate(val, p);
      else if (name === "DTEND") cur.end = pdate(val, p);
      else if (name === "DURATION") cur.dur = val;
      else if (name === "SUMMARY") cur.sum = unesc(val);
      else if (name === "RRULE") cur.rrule = val;
      else if (name === "EXDATE") { for (const v of val.split(",")) { const d = pdate(v, p); if (d) cur.ex.push(d.d.getTime()); } }
      else if (name === "RECURRENCE-ID") cur.rid = pdate(val, p);
      else if (name === "UID") cur.uid = val;
      else if (name === "STATUS") cur.status = val;
    }
    return evs;
  }
  const DC = ["SU","MO","TU","WE","TH","FR","SA"];
  function occs(ev, from, to, dur) {
    const s = ev.start.d, out = [];
    if (!ev.rrule) { out.push(s); return out; }
    const r = {}; ev.rrule.split(";").forEach(kv => { const [k, v] = kv.split("="); r[k] = v; });
    const iv = +(r.INTERVAL || 1), cnt = r.COUNT ? +r.COUNT : 1e9;
    let until = r.UNTIL ? pdate(r.UNTIL) : null;
    if (until) until = until.all ? new Date(until.d.getTime() + 864e5 - 1) : until.d;
    const H = s.getHours(), Mi = s.getMinutes(), Se = s.getSeconds();
    const at = (y, m, d) => new Date(y, m, d, H, Mi, Se);
    const byday = r.BYDAY ? r.BYDAY.split(",") : null;
    let n = 0, guard = 0;
    const emit = o => { if (o < s) return true; if (until && o > until) return false; if (n >= cnt || o >= to) return false; n++; if (o.getTime() + Math.max(dur, 1) > from) out.push(o); return true; };
    const y0 = s.getFullYear(), m0 = s.getMonth(), d0 = s.getDate();
    if (r.FREQ === "DAILY") {
      for (let k = 0; guard++ < 200000; k += iv) { const o = at(y0, m0, d0 + k); if (byday && !byday.some(b => b.slice(-2) === DC[o.getDay()])) continue; if (!emit(o)) break; }
    } else if (r.FREQ === "WEEKLY") {
      const days = byday ? byday.map(b => DC.indexOf(b.slice(-2))).sort((a, b) => a - b) : [s.getDay()];
      const w0 = d0 - s.getDay();
      outer: for (let k = 0; guard++ < 20000; k += 7 * iv) for (const wd of days) if (!emit(at(y0, m0, w0 + k + wd))) break outer;
    } else if (r.FREQ === "MONTHLY") {
      outer: for (let k = 0; guard++ < 5000; k += iv) {
        const base = new Date(y0, m0 + k, 1), y = base.getFullYear(), m = base.getMonth(), dim = new Date(y, m + 1, 0).getDate(), list = [];
        if (byday) {
          for (const b of byday) {
            const mm = b.match(/^([+-]?\d+)?(\w\w)$/); if (!mm) continue;
            const wd = DC.indexOf(mm[2]), nth = mm[1] ? +mm[1] : 0, ds = [];
            for (let d = 1; d <= dim; d++) if (new Date(y, m, d).getDay() === wd) ds.push(d);
            if (nth > 0) { if (ds[nth - 1]) list.push(ds[nth - 1]); } else if (nth < 0) { if (ds[ds.length + nth]) list.push(ds[ds.length + nth]); } else list.push(...ds);
          }
        } else {
          const md = r.BYMONTHDAY ? r.BYMONTHDAY.split(",").map(Number) : [d0];
          for (const d of md) { const dd = d < 0 ? dim + 1 + d : d; if (dd >= 1 && dd <= dim) list.push(dd); }
        }
        list.sort((a, b) => a - b);
        for (const d of list) if (!emit(at(y, m, d))) break outer;
      }
    } else if (r.FREQ === "YEARLY") {
      for (let k = 0; guard++ < 1000; k += iv) { const y = y0 + k; if (d0 > new Date(y, m0 + 1, 0).getDate()) continue; if (!emit(at(y, m0, d0))) break; }
    } else out.push(s);
    return out;
  }
  function loadIcs(text) {
    icsText = text; setTimeout(rfDone, 0);
    const win = gWin(), from = win.from, to = win.to;
    const all = icsParse(text).filter(e => e.start);
    const overridden = new Set(all.filter(e => e.rid && e.uid).map(e => e.uid + "|" + e.rid.d.getTime()));
    const out = [];
    for (const e of all) {
      if (e.status === "CANCELLED") continue;
      const dur = e.end ? e.end.d - e.start.d : (e.dur ? pdur(e.dur) : (e.start.all ? 864e5 : 0));
      for (const o of occs(e, from, to, dur)) {
        const t = o.getTime();
        if (e.ex.includes(t)) continue;
        if (!e.rid && e.rrule && overridden.has(e.uid + "|" + t)) continue;
        const end = new Date(t + dur);
        if (o >= to || (end <= from && !(dur === 0 && o >= from))) continue;
        out.push({ s: o, e: end, all: e.start.all, title: e.sum || "(제목 없음)", color: null, id: e.uid });
      }
    }
    gEvents = out; gError = ""; renderAll();
  }

  function renderG() {
    const body = $("gBody");
    $("gOpen").hidden = gmode !== "google";
    let html = "", chHtml = "";
    const loginBlock = (note) => `<div class="gblk">
        <p class="empty" style="margin:0">${note}</p>
        <button class="gbtn" type="button" data-g="glogin"><svg viewBox="0 0 48 48" aria-hidden="true"><path fill="#EA4335" d="M24 9.5c3.5 0 6.6 1.2 9.1 3.6l6.8-6.8C35.8 2.4 30.3 0 24 0 14.6 0 6.6 5.4 2.7 13.3l7.9 6.1C12.5 13.6 17.8 9.5 24 9.5z"/><path fill="#4285F4" d="M46.1 24.5c0-1.6-.1-3.1-.4-4.5H24v9h12.4c-.5 2.9-2.2 5.3-4.6 6.9l7.4 5.7c4.3-4 6.9-9.9 6.9-17.1z"/><path fill="#FBBC05" d="M10.6 28.6c-.5-1.4-.8-3-.8-4.6s.3-3.2.8-4.6l-7.9-6.1C1 16.6 0 20.2 0 24s1 7.4 2.7 10.7l7.9-6.1z"/><path fill="#34A853" d="M24 48c6.5 0 11.9-2.1 15.8-5.8l-7.4-5.7c-2.1 1.4-4.8 2.2-8.4 2.2-6.2 0-11.5-4.1-13.4-9.9l-7.9 6.1C6.6 42.6 14.6 48 24 48z"/></svg>Google 계정으로 로그인</button>
        <label class="check" for="gAutoChk"><input type="checkbox" id="gAutoChk"${gAutoLogin ? " checked" : ""}>자동 로그인 <span style="font-size:11.5px;color:var(--muted);font-weight:500">위젯을 다시 켜도 자동으로 연결돼요</span></label>
        <button class="link" type="button" data-g="gical">iCal 주소로 연결</button>
      </div>`;
    if (!gmode) {
      html = loginBlock("구글 캘린더를 연결하면 내 일정이 여기에 보여요.");
    } else if (gmode === "google" && gStatus === "client") {
      html = loginBlock("처음 한 번 구글 클라우드 설정 파일이 필요해요. 로그인을 누르면 파일을 고를 수 있어요.") +
        `<button class="link" type="button" data-g="gguide">설정 방법 보기</button>`;
    } else if (gmode === "google" && gStatus === "login") {
      html = loginBlock("구글 로그인이 필요해요.");
    } else if (gError) {
      html = `<p class="msg err">${esc(gError)}</p><div class="btnrow"><button class="btn" type="button" data-g="retry">다시 시도</button></div>`;
    } else if (!gEvents) {
      html = `<p class="empty" style="margin:0">${gStatus === "waiting" ? "브라우저에서 구글 로그인을 마쳐 주세요…" : "불러오는 중…"}</p>`;
    } else {
      const now = new Date(), t0 = new Date(); t0.setHours(0, 0, 0, 0);
      const groups = new Map();
      const showCals = gmode === "google";
      const offIds = new Set(gCals.filter(c => !calOn(c)).map(c => c.id));
      const chip = c =>
          `<button type="button" class="cchip" role="checkbox" aria-checked="${calOn(c)}" data-cal="${esc(c.id)}" title="${esc(c.name)} · 더블클릭하면 초대 링크" style="--c:${esc(c.color || "var(--accent)")}"><i></i><span>${esc(c.name)}</span></button>`;
      if (showCals) {
        const own = gCals.filter(c => !c.team), team = gCals.filter(c => c.team);
        if (own.length || gmode === "google") chHtml += `<div class="cchips" role="group" aria-label="표시할 캘린더">` + own.map(chip).join("") +
          (gmode === "google" ? `<button type="button" class="cchip add" id="gNewChip" title="내 구글 캘린더에 새 캘린더 만들기"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" aria-hidden="true"><path d="M12 5v14M5 12h14"/></svg><span>새 캘린더</span></button>` : "") + `</div>`;
        if (team.length) chHtml += `<div class="gsub">${esc(tcCfg && tcCfg.name || "팀 그룹")}</div><div class="cchips" role="group" aria-label="${esc(tcCfg && tcCfg.name || "팀 그룹")} 캘린더">` + team.map(chip).join("") + `</div>`;
      }
      const tEnd = new Date(t0); tEnd.setDate(tEnd.getDate() + 14);
      html += `<div class="gup" id="gUp">`;
      for (const ev of gEvents) {
        if (ev.cal && offIds.has(ev.cal)) continue;
        if (ev.e <= t0 && !(ev.e - ev.s === 0 && ev.s >= t0)) continue;
        if (ev.s >= tEnd) continue;
        let d = ev.s < t0 ? new Date(t0) : new Date(ev.s.getFullYear(), ev.s.getMonth(), ev.s.getDate());
        if (ymd(d) === selected) continue;
        if (ev.all && ev.e <= now && ev.e - ev.s <= 864e5 && ev.s < t0) continue;
        const k = d.getTime(); if (!groups.has(k)) groups.set(k, []); groups.get(k).push(ev);
      }
      // 다가오는 팀원 휴가 (시작일에 한 번만. 선택한 날은 위 부재 줄에 있으니 다음 날부터)
      if (loaded) {
        const tEndS = ymd(new Date(tEnd.getTime() - 864e5));
        for (const lv of entries()) {
          if (lv.end < today || lv.start > tEndS) continue;
          let ds = lv.start < today ? today : lv.start;
          if (ds === selected) { if (lv.end <= selected) continue; const nx = parse(selected); nx.setDate(nx.getDate() + 1); ds = ymd(nx); }
          if (ds > tEndS) continue;
          const k = parse(ds).getTime(); if (!groups.has(k)) groups.set(k, []);
          groups.get(k).push({ leave: lv });
        }
      }
      const keys = [...groups.keys()].sort((a, b) => a - b);
      let shown = 0;
      for (const k of keys) {
        const list = groups.get(k).sort((a, b) => (!!a.leave - !!b.leave) || (a.leave ? 0 : ((b.all - a.all) || (a.s - b.s))));
        const d = new Date(k), diff = Math.round((k - t0) / 864e5);
        html += `<div class="gday${diff === 0 ? " today" : ""}">${diff === 0 ? "오늘" : diff === 1 ? "내일" : `${d.getMonth()+1}.${d.getDate()} ${DOW[d.getDay()]}`}</div>`;
        for (const ev of list) {
          if (ev.leave) {
            const lv = ev.leave, mine = me && lv.uid === me.id;
            const range = lv.start !== lv.end ? ` · ${fmtShort(lv.start)}~${fmtShort(lv.end)}` : "";
            html += `<div class="lv${mine || isMyTeam(lv.uid) ? "" : " out"}"><i class="${mine ? "me" : (isMyTeam(lv.uid) ? "" : "out")}" aria-hidden="true"></i><span class="tm">휴가</span><span class="ti" title="${esc(lv.memo)}">${esc(mine ? "나" : lv.who)} ${esc(lv.type)}${range}${isMyTeam(lv.uid) ? "" : " (팀 밖)"}</span></div>`;
          } else html += evRow(ev, d);
          shown++;
        }
      }
      if (!keys.length) html += `<p class="empty" style="margin:0">${offIds.size ? "표시할 일정이 없어요." : "앞으로 2주 동안 다른 일정·휴가가 없어요."}</p>`;
      html += `</div>`;
      upCount = shown;
    }
    $("gAddBtn").hidden = !(gmode === "google" && gEvents && !gError && gWritable.length);
    const connected = gmode === "ical" || (gmode === "google" && gStatus !== "login" && gStatus !== "client");
    $("gOut").hidden = true;      // 로그아웃·연결 해제는 설정 창(캘린더 탭)에서
    $("gHead").textContent = connected ? "다가오는 일정 · 휴가" : "내 일정";
    $("gCh").setAttribute("aria-label", connected ? "다가오는 일정 접기" : "내 일정 접기");
    $("gOut").textContent = gmode === "ical" ? "연결 해제" : "로그아웃";
    body.innerHTML = html;
    const ac = body.querySelector("#gAutoChk");
    if (ac) ac.onchange = () => { gAutoLogin = ac.checked; host({ cmd: "gauto", on: ac.checked }); };
    bindEvRows(body);
    const gu = body.querySelector("#gUp"); if (gu) gu.addEventListener("scroll", upFade, { passive: true });
    const cc = $("calChips"); cc.innerHTML = chHtml;
    const nc = cc.querySelector("#gNewChip"); if (nc) nc.onclick = () => openNewCalPop(nc);
    body.querySelectorAll("[data-hint]").forEach(b => b.onclick = () => {
      if (b.dataset.hint === "group") host({ cmd: "open", url: TEAM_GROUP });
      else { lsSet("tlw.hintOff", "1"); renderG(); toast("메뉴 › 내 일정 › 팀 캘린더 안내 다시 보기로 다시 볼 수 있어요"); }
    });
    cc.querySelectorAll("[data-cal]").forEach(b => {
      const toggle = () => {
        const c = gCals.find(x => x.id === b.dataset.cal); if (!c) return;
        calPref[c.id] = !calOn(c);
        try { localStorage.setItem("tlw.calPref", JSON.stringify(calPref)); } catch (e) {}
        renderAll();
        const nb = $("calChips").querySelector(`[data-cal="${CSS.escape(c.id)}"]`); if (nb) nb.focus();
      };
      // 한 번 클릭 = 보이기/숨기기, 더블클릭 = 초대 링크 (더블클릭일 땐 토글하지 않음)
      b.onclick = e => {
        if (e.detail === 0) { toggle(); return; }       // 키보드(Enter/Space)
        clearTimeout(chipTimer); chipTimer = setTimeout(toggle, 260);
      };
      b.ondblclick = e => { e.preventDefault(); clearTimeout(chipTimer); openInvite(b.dataset.cal); };
      b.onkeydown = e => { if (e.key === "i" || e.key === "I") { e.preventDefault(); openInvite(b.dataset.cal); } };
    });
    body.querySelectorAll("[data-g]").forEach(b => b.onclick = () => {
      const a = b.dataset.g;
      if (a === "retry") gRequest(); else host({ cmd: a });
    });
    report();
  }
  const hhmm = d => `${pad(d.getHours())}:${pad(d.getMinutes())}`;

  // ---------------- 팀 캘린더 같이 보기 (그룹 가입 → 캘린더 추가) ----------------
  const TEAM_GROUP = "https://groups.google.com/g/aaarchi2";
  const lsGet = k => { try { return localStorage.getItem(k); } catch (e) { return null; } };
  const lsSet = (k, v) => { try { if (v == null) localStorage.removeItem(k); else localStorage.setItem(k, v); } catch (e) {} };
  function setTeamCal(cfg) {
    let cals = [];
    if (cfg && Array.isArray(cfg.cals)) cals = cfg.cals;
    else if (cfg && cfg.cal) cals = [{ id: cfg.cal, name: cfg.name, color: cfg.color }];     // 1.8.0 형식
    cals = cals.filter(c => c && typeof c.id === "string" && c.id)
      .map(c => ({ id: c.id, name: String(c.name || ""), color: /^#[0-9a-f]{3,8}$/i.test(c.color || "") ? c.color : "" }));
    const before = JSON.stringify(tcCfg);
    tcCfg = cals.length ? { name: String((cfg && cfg.name) || ""), cals } : null;
    if (POPUP || JSON.stringify(tcCfg) === before) return;
    if (gmode === "google" && gToken) gRequest(); else renderG();
  }

  // ---------------- 다른 사람이 캘린더를 바꾸면 알림 ----------------
  // 개인 '내 캘린더'와 공휴일·생일 같은 자동 캘린더를 뺀 캘린더의 앞으로 2주 일정을, 지난번과 비교한다
  const selfKeys = new Set(), selfAdds = [];
  function selfMark(cal, id) { selfKeys.add(`${cal}|${id}`); }
  function selfFrom(ids) {
    for (const x of ids || []) {
      const p = String(x).split("|");
      if (p[0] === "add") selfAdds.push({ cal: p[1], title: p.slice(2).join("|"), at: Date.now() });
      else if (p.length >= 2) selfMark(p[0], p.slice(1).join("|"));
    }
  }
  let ntItems = [];
  const WD = "일월화수목금토";
  const fmtWhen = it => { const d = new Date(it.s); return `${d.getMonth() + 1}/${d.getDate()}(${WD[d.getDay()]})${it.a ? "" : " " + hhmm(d)}`; };
  function watchChanges(events, primary) {
    const acct = primary ? primary.id : "";
    const t0 = new Date(); t0.setHours(0, 0, 0, 0);
    const t1 = new Date(t0); t1.setDate(t1.getDate() + 14);
    const watched = gCals.filter(c => !c.primary && !c.team && !/@group\.v\.calendar\.google\.com$/.test(c.id) && !/#(contacts|holiday|weeknum)/.test(c.id));
    const wIds = new Set(watched.map(c => c.id));
    const items = {};
    for (const ev of events) {
      if (!wIds.has(ev.cal) || !ev.id || ev.s < t0 || ev.s >= t1) continue;
      items[`${ev.cal}|${ev.id}`] = { t: ev.title, s: ev.s.getTime(), e: ev.e.getTime(), a: ev.all ? 1 : 0, c: ev.cal };
    }
    const snap = { acct, from: t0.getTime(), to: t1.getTime(), cals: [...wIds], items };
    let prev = null; try { prev = JSON.parse(localStorage.getItem("tlw.gSnap") || "null"); } catch (e) {}
    try { localStorage.setItem("tlw.gSnap", JSON.stringify(snap)); } catch (e) {}
    if (!prev || prev.acct !== acct || !prev.items) return;
    const from = Math.max(prev.from, snap.from), to = Math.min(prev.to, snap.to);
    const both = new Set((prev.cals || []).filter(c => wIds.has(c)));
    const inWin = it => it.s >= from && it.s < to && both.has(it.c);
    const out = [];
    for (const [k, it] of Object.entries(items)) {
      if (!inWin(it) || selfKeys.has(k)) continue;
      const old = prev.items[k];
      if (!old) {
        const ai = selfAdds.findIndex(x => (x.cal === it.c || x.cal === "primary") && x.title === it.t && Date.now() - x.at < 15 * 60000);
        if (ai >= 0) { selfAdds.splice(ai, 1); continue; }
        out.push({ kind: "추가", ...it });
      } else if (old.t !== it.t || old.s !== it.s || old.e !== it.e || old.a !== it.a) {
        out.push({ kind: "변경", ...it, old });
      }
    }
    for (const [k, old] of Object.entries(prev.items)) {
      if (!inWin(old) || items[k] || selfKeys.has(k)) continue;
      if (old.s < snap.from) continue;
      out.push({ kind: "삭제", ...old });
    }
    selfKeys.clear();
    if (!out.length || lsGet("tlw.ntOn") === "0") return;
    out.sort((a, b) => a.s - b.s);
    ntItems = out.concat(ntItems.filter(o => !out.some(n => n.c === o.c && n.t === o.t && n.s === o.s))).slice(0, 20);
    renderNotice();
    const cals = [...new Set(out.map(x => x.c))];
    const nm = c => (gCals.find(x => x.id === c) || {}).name || "캘린더";
    const title = cals.length === 1 ? `${nm(cals[0])} 캘린더가 바뀌었어요` : `캘린더 ${cals.length}개가 바뀌었어요`;
    const first = out[0];
    if (lsGet("tlw.ntWin") !== "0") host({ cmd: "notify", title, text: `${first.kind} · ${first.t} ${fmtWhen(first)}${out.length > 1 ? ` 외 ${out.length - 1}건` : ""}` });
  }
  function renderNotice() {
    const box = $("ntBox"); if (!box) return;
    if (!ntItems.length) { box.replaceChildren(); report(); return; }
    const cals = [...new Set(ntItems.map(x => x.c))];
    const cal = c => gCals.find(x => x.id === c) || { name: "캘린더", color: "" };
    const one = cals.length === 1;
    const title = one ? `${cal(cals[0]).name} 캘린더가 바뀌었어요` : `캘린더 ${cals.length}개가 바뀌었어요`;
    const shown = ntItems.slice(0, 4);
    const go = ntItems.find(x => x.kind !== "삭제");
    const li = it => {
      const d = new Date(it.s);
      let when = fmtWhen(it);
      if (it.kind === "변경" && it.old) {
        const od = new Date(it.old.s);
        if (it.old.s !== it.s || it.old.e !== it.e) when = (ymd(od) !== ymd(d) ? fmtWhen(it.old) + " → " + fmtWhen(it) : fmtWhen(it.old) + " → " + (it.a ? "종일" : hhmm(d)));
        else if (it.old.t !== it.t) when += ` · '${it.old.t}'에서 이름 변경`;
      }
      return `<li>${one ? "" : `<i style="--c:${esc(cal(it.c).color || "var(--accent)")}"></i>`}<b>${it.kind}</b> ${esc(it.t)} <span>· ${esc(when)}</span></li>`;
    };
    box.innerHTML = `<div class="nt" style="--c:${esc(one ? (cal(cals[0]).color || "var(--accent)") : "var(--accent)")}"><div class="h"><i></i><b>${esc(title)}</b><small>${new Date().getHours()}:${pad(new Date().getMinutes())}</small></div>
      <ul>${shown.map(li).join("")}${ntItems.length > 4 ? `<li style="list-style:none;margin-left:-15px;color:var(--muted)">외 ${ntItems.length - 4}건</li>` : ""}</ul>
      <div class="a">${go ? `<button type="button" data-nt="go">${new Date(go.s).getMonth() + 1}/${new Date(go.s).getDate()}로 가기</button>` : ""}<button type="button" class="g" data-nt="ok">확인</button></div></div>`;
    box.querySelectorAll("[data-nt]").forEach(b => b.onclick = () => {
      if (b.dataset.nt === "go" && go) { const d = new Date(go.s); selected = ymd(d); view = new Date(d.getFullYear(), d.getMonth(), 1); monthChanged(); }
      ntItems = []; renderNotice();
    });
    report();
  }

  // ---------------- 캘린더별 데드라인 (각 캘린더의 마지막 일정까지 D-day) ----------------
  // 반복 일정은 빼고, 오늘 이후 2년 안의 마지막 일정 = 마감, 2년 전부터의 첫 일정 = 시작
  let dlData = {}, dlAt = 0, dlKey = "";
  function dlPref() { try { return JSON.parse(localStorage.getItem("tlw.dl") || "{}") || {}; } catch (e) { return {}; } }
  function dlEligible() { return gCals.filter(c => !/@group\.v\.calendar\.google\.com$/.test(c.id) && !/#(contacts|holiday|weeknum)/.test(c.id)); }
  function dlOn(c) { const p = dlPref(); return c.id in p ? !!p[c.id] : !c.primary; }   // 기본: 개인 '내 캘린더'만 끔
  function setDlOn(id, on) { const p = dlPref(); p[id] = !!on; try { localStorage.setItem("tlw.dl", JSON.stringify(p)); } catch (e) {} renderDeadlines(); report(); }
  async function loadDeadlines(force) {
    if (gmode !== "google" || !gToken) { dlData = {}; renderDeadlines(); return; }
    const cals = dlEligible();
    const key = cals.map(c => c.id).sort().join("|");
    if (!force && key === dlKey && Date.now() - dlAt < 30 * 60000) { renderDeadlines(); return; }
    dlKey = key; dlAt = Date.now();
    const t0 = new Date(); t0.setHours(0, 0, 0, 0);
    const far = new Date(t0); far.setFullYear(far.getFullYear() + 2);
    const back = new Date(t0); back.setFullYear(back.getFullYear() - 2);
    const when = st => st && st.dateTime ? new Date(st.dateTime) : (st && st.date ? parse(st.date) : null);
    const q = (id, params) => gfetch(`https://www.googleapis.com/calendar/v3/calendars/${encodeURIComponent(id)}/events?singleEvents=true&orderBy=startTime&${params}`, gToken);
    const next = {};
    await Promise.all(cals.map(async c => {
      try {
        let items = [], page = "", n = 0;
        do {
          const r = await q(c.id, `timeMin=${encodeURIComponent(t0.toISOString())}&timeMax=${encodeURIComponent(far.toISOString())}&maxResults=2500&fields=items(summary,start,recurringEventId,status),nextPageToken${page ? "&pageToken=" + encodeURIComponent(page) : ""}`);
          items = items.concat(r.items || []); page = r.nextPageToken || ""; n++;
        } while (page && n < 4);
        const once = items.filter(e => !e.recurringEventId && e.status !== "cancelled" && when(e.start));
        if (!once.length) return;
        const last = once[once.length - 1];
        const r2 = await q(c.id, `timeMin=${encodeURIComponent(back.toISOString())}&maxResults=100&fields=items(start,recurringEventId,status)`);
        const first = (r2.items || []).find(e => !e.recurringEventId && e.status !== "cancelled" && when(e.start)) || once[0];
        next[c.id] = { first: when(first.start), last: when(last.start), title: last.summary || "(제목 없음)" };
      } catch (e) { if (e.auth) throw e; }
    })).catch(() => {});
    dlData = next; renderDeadlines(); report();
  }
  function renderDeadlines() {
    const box = $("dlBox"); if (!box) return;
    const t0 = new Date(); t0.setHours(0, 0, 0, 0);
    const list = gmode === "google" ? dlEligible().filter(c => dlData[c.id] && dlOn(c)).map(c => ({ c, ...dlData[c.id] })) : [];
    list.sort((a, b) => a.last - b.last);
    const shown = list.slice(0, 4);
    $("yrYear").hidden = shown.length > 0;
    if (!shown.length) { box.replaceChildren(); return; }
    const md = d => `${d.getMonth() + 1}.${pad(d.getDate())}`;
    box.innerHTML = shown.map(({ c, first, last, title }) => {
      const L = new Date(last); L.setHours(0, 0, 0, 0);
      const F = new Date(first); F.setHours(0, 0, 0, 0);
      const left = Math.round((L - t0) / 864e5);
      const total = Math.max(1, Math.round((L - F) / 864e5));
      const done = Math.min(total, Math.max(0, Math.round((t0 - F) / 864e5)));
      const k = Math.min(11, Math.floor(done / total * 12));
      const segs = Array.from({ length: 12 }, (_, i) => `<span class="${i < k ? "done" : (i === k ? "now" : "")}"></span>`).join("");
      const dd = left > 0 ? `D-${left}` : (left === 0 ? "D-day" : `D+${-left}`);
      return `<div class="dli" role="button" tabindex="0" data-dl="${esc(c.id)}" style="--c:${esc(c.color || "var(--accent)")}" title="마지막 일정: ${esc(title)} (${md(L)}) · 누르면 그 날짜로">
        <div class="dlh"><i></i><span class="nm">${esc(c.name.replace(/ \(기본\)$/, ""))}</span><span class="tt">${esc(title)}</span><b class="${left < 0 ? "past" : ""}">${dd}</b><span class="off" role="button" tabindex="0" data-dloff="${esc(c.id)}" aria-label="${esc(c.name)} 데드라인 끄기" title="이 캘린더 데드라인 끄기"><svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round"><path d="M6 6l12 12M18 6L6 18"/></svg></span></div>
        <div class="yb" aria-hidden="true">${segs}</div>
        <div class="yl"><span>${md(F)} 시작 · ${done + 1}일째</span><span>${md(L)}(${"일월화수목금토"[L.getDay()]})${left >= 0 ? `까지 ${left}일` : " 지남"}</span></div></div>`;
    }).join("");
    box.querySelectorAll("[data-dloff]").forEach(x => x.onclick = e => {
      e.stopPropagation(); setDlOn(x.dataset.dloff, false);
      toast("설정 › 캘린더 › 데드라인에서 다시 켤 수 있어요");
    });
    box.querySelectorAll("[data-dl]").forEach(x => {
      const go = () => { const d = dlData[x.dataset.dl]; if (!d) return; const L = new Date(d.last); selected = ymd(L); view = new Date(L.getFullYear(), L.getMonth(), 1); monthChanged(); };
      x.onclick = go; x.onkeydown = e => { if (e.key === "Enter" || e.key === " ") { e.preventDefault(); go(); } };
    });
  }

  // ---------------- 새 캘린더 만들기 (내 일정 칩 줄) ----------------
  async function createCal(name, color) {
    const tz = Intl.DateTimeFormat().resolvedOptions().timeZone || "Asia/Seoul";
    const r = await fetch("https://www.googleapis.com/calendar/v3/calendars", {
      method: "POST", headers: { Authorization: "Bearer " + gToken, "Content-Type": "application/json" }, body: JSON.stringify({ summary: name, timeZone: tz })
    });
    if (r.status === 401 || r.status === 403) return { relogin: true };
    if (!r.ok) throw new Error("HTTP " + r.status);
    const cal = await r.json();
    try {
      await fetch(`https://www.googleapis.com/calendar/v3/users/me/calendarList/${encodeURIComponent(cal.id)}?colorRgbFormat=true`, {
        method: "PATCH", headers: { Authorization: "Bearer " + gToken, "Content-Type": "application/json" }, body: JSON.stringify({ backgroundColor: color, foregroundColor: "#ffffff" })
      });
    } catch (e) {}
    return { cal };
  }
  function openNewCalPop(anchor) {
    closeInvite();
    let ci = 0;
    const d = document.createElement("div");
    d.className = "ipop"; d.setAttribute("role", "dialog"); d.setAttribute("aria-label", "새 캘린더 만들기");
    d.innerHTML = `<div class="ih"><span>새 캘린더 만들기</span><button class="x" type="button" aria-label="닫기"><svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"><path d="M6 6l12 12M18 6L6 18"/></svg></button></div>
      <div class="il">캘린더 이름</div>
      <div class="ir"><input class="nm" maxlength="100" placeholder="예: 국립디자인, 현장 일정" autocomplete="off" style="color:var(--fg)"></div>
      <div class="sw2" role="radiogroup" aria-label="캘린더 색상">${SWATCH.map((c, i) => `<button type="button" role="radio" aria-checked="${i === 0}" aria-label="색 ${i + 1}" style="--c:${c}" data-i="${i}"></button>`).join("")}</div>
      <p class="msg2" role="status"></p>
      <div class="act2"><button type="button" class="cn">취소</button><button type="button" class="pri ok">만들기</button></div>`;
    const r = anchor.getBoundingClientRect();
    d.style.top = (r.bottom + window.scrollY + 8) + "px";
    document.body.appendChild(d);
    const inp = d.querySelector(".nm"), ok = d.querySelector(".ok"), m = d.querySelector(".msg2");
    const say = (t, err) => { m.textContent = t; m.className = "msg2" + (err ? " err" : ""); report(); };
    d.querySelectorAll(".sw2 button").forEach(b => b.onclick = () => { ci = +b.dataset.i; d.querySelectorAll(".sw2 button").forEach(x => x.setAttribute("aria-checked", x === b ? "true" : "false")); });
    const close = () => { closeInvite(); anchor.focus(); };
    d.querySelector(".x").onclick = close; d.querySelector(".cn").onclick = close;
    d.addEventListener("keydown", e => { if (e.key === "Escape") close(); else if (e.key === "Enter" && e.target === inp) ok.click(); });
    ok.onclick = async () => {
      const name = inp.value.trim();
      if (!name) { say("캘린더 이름을 입력하세요.", true); inp.focus(); return; }
      if (!gToken) { say("구글에 연결하는 중이에요. 잠시 후 다시 눌러 주세요.", true); host({ cmd: "gtoken" }); return; }
      ok.disabled = true; say("만드는 중…");
      try {
        const res = await createCal(name, SWATCH[ci]);
        if (res.relogin) { say("새 캘린더를 만들 권한이 없어요. 구글에 한 번 더 로그인해 주세요.", true); ok.textContent = "구글 다시 로그인"; ok.disabled = false; ok.onclick = () => host({ cmd: "glogin" }); return; }
        closeInvite(); toast(`'${name}' 캘린더를 만들었어요`); gRequest();
      } catch (e) { say("캘린더를 만들지 못했어요. 잠시 후 다시 시도해 주세요.", true); ok.disabled = false; }
    };
    setTimeout(() => document.addEventListener("mousedown", inviteOutside, true), 0);
    inp.focus(); report();
  }

  // ---------------- 캘린더 초대 링크 (칩 더블클릭) ----------------
  let chipTimer = null;
  const b64id = id => btoa(unescape(encodeURIComponent(id))).replace(/=+$/, "");
  function closeInvite() { const o = document.querySelector(".ipop"); if (o) o.remove(); document.removeEventListener("mousedown", inviteOutside, true); }
  function inviteOutside(e) { if (!e.target.closest(".ipop") && !e.target.closest(".cchip")) closeInvite(); }
  function openInvite(id) {
    closeInvite();
    const c = gCals.find(x => x.id === id), chip = $("calChips").querySelector(`[data-cal="${CSS.escape(id)}"]`);
    if (!c || !chip) return;
    const link = "https://calendar.google.com/calendar/u/0?cid=" + b64id(c.id);
    const settings = "https://calendar.google.com/calendar/u/0/r/settings/calendar/" + b64id(c.id);
    const d = document.createElement("div");
    d.className = "ipop"; d.setAttribute("role", "dialog"); d.setAttribute("aria-label", `${c.name} 초대 링크`);
    d.style.setProperty("--c", c.color || "var(--accent)");
    d.innerHTML = `<div class="ih"><i></i><span>${esc(c.name)}</span><button class="x" type="button" aria-label="닫기"><svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"><path d="M6 6l12 12M18 6L6 18"/></svg></button></div>
      <div class="il">캘린더 초대 링크</div>
      <div class="ir"><input readonly value="${esc(link)}" aria-label="초대 링크"><button class="cp" type="button">복사</button></div>
      <p>링크를 받은 사람이 열면 이 캘린더가 그 사람 구글 캘린더에 추가돼요.<br>처음 한 번은 공유 설정에서 그 사람 이메일을 추가해 줘야 일정이 보여요.</p>
      <button class="so" type="button">공유 설정 열기 ↗</button>`;
    const r = chip.getBoundingClientRect();
    d.style.top = (r.bottom + window.scrollY + 8) + "px";
    document.body.appendChild(d);
    const inp = d.querySelector("input"), cp = d.querySelector(".cp");
    inp.onfocus = () => inp.select();
    cp.onclick = async () => { await copyText(link); cp.textContent = "복사됨 ✓"; setTimeout(() => { cp.textContent = "복사"; }, 1800); };
    d.querySelector(".so").onclick = () => host({ cmd: "open", url: settings });
    d.querySelector(".x").onclick = () => { closeInvite(); chip.focus(); };
    d.addEventListener("keydown", e => { if (e.key === "Escape") { closeInvite(); chip.focus(); } });
    setTimeout(() => document.addEventListener("mousedown", inviteOutside, true), 0);
    cp.focus(); report();
  }

  // ---------------- 구글 일정 추가 ----------------
  let gPendingSave = null, gSelCal = null, gSwIdx = 0;
  const SWATCH = ["#e0592a", "#2f6fdb", "#178a6b", "#8e5bd6", "#d2a01b", "#c23b4a"];
  function gCalc(text, err) { const o = $("gCalc"); o.textContent = text || ""; o.className = "calc" + (err ? " err" : ""); }
  function renderGCals() {
    const box = $("gCals"); box.replaceChildren();
    for (const c of gWritable) {
      const b = document.createElement("button"); b.type = "button"; b.className = "chip" + (c.id === gSelCal ? " on" : "");
      b.textContent = c.name; b.setAttribute("role", "radio"); b.setAttribute("aria-checked", c.id === gSelCal ? "true" : "false");
      b.onclick = () => { gSelCal = c.id; renderGCals(); };
      box.append(b);
    }
    if ($("gNew").hidden) {
      const add = document.createElement("button"); add.type = "button"; add.className = "chip add";
      add.innerHTML = '<svg viewBox="0 0 24 24" fill="none" stroke-width="2.6" stroke-linecap="round" aria-hidden="true"><path d="M12 5v14M5 12h14"/></svg>새 캘린더';
      add.onclick = openNewCal; box.append(add);
    }
  }
  function renderSwatches() {
    const sw = $("gSw"); sw.replaceChildren();
    SWATCH.forEach((c, i) => {
      const b = document.createElement("button"); b.type = "button"; b.style.setProperty("--c", c);
      b.setAttribute("role", "radio"); b.setAttribute("aria-checked", i === gSwIdx ? "true" : "false"); b.setAttribute("aria-label", "색상 " + (i + 1));
      b.onclick = () => { gSwIdx = i; renderSwatches(); };
      sw.append(b);
    });
  }
  function openNewCal() { $("gNew").hidden = false; $("gNewName").value = ""; msg($("gNewMsg"), ""); gSwIdx = 0; renderSwatches(); renderGCals(); setTimeout(() => $("gNewName").focus(), 20); }
  function closeNewCal() { $("gNew").hidden = true; renderGCals(); }
  $("gNewCancel").onclick = closeNewCal;
  $("gNewOk").onclick = async () => {
    const name = $("gNewName").value.trim();
    if (!name) { msg($("gNewMsg"), "캘린더 이름을 입력하세요.", "err"); $("gNewName").focus(); return; }
    if (!gToken) { msg($("gNewMsg"), "구글에 연결하는 중이에요. 잠시 후 다시 눌러 주세요.", "err"); host({ cmd: "gtoken" }); return; }
    $("gNewOk").disabled = true; msg($("gNewMsg"), "만드는 중…");
    try {
      const color = SWATCH[gSwIdx];
      const res = await createCal(name, color);
      if (res.relogin) {
        msg($("gNewMsg"), "새 캘린더를 만들 권한이 없어요. 구글에 한 번 더 로그인해서 권한을 허용해 주세요.", "err");
        $("gNewOk").textContent = "구글 다시 로그인"; $("gNewOk").disabled = false; $("gNewOk").onclick = () => host({ cmd: "glogin" }); return;
      }
      const cal = res.cal;
      gWritable.push({ id: cal.id, name, color }); gSelCal = cal.id;
      closeNewCal(); gCalc(`'${name}' 캘린더를 만들었어요.`);
    } catch (e) { msg($("gNewMsg"), "캘린더를 만들지 못했어요. 잠시 후 다시 시도해 주세요.", "err"); }
    finally { if ($("gNewOk").textContent === "만들기" || $("gNewOk").textContent === "") $("gNewOk").disabled = false; }
  };

  // 일정 수정: 더블클릭한 일정의 내용을 담아 같은 창을 '수정' 모드로 연다
  let gEdit = null;
  function openEdit(ev) {
    if (!ev || !ev.id || !gWritable.some(c => c.id === ev.cal)) return;
    const d0 = new Date(ev.s.getFullYear(), ev.s.getMonth(), ev.s.getDate());
    const eDay = ev.all ? new Date(ev.e.getTime() - 864e5) : ev.e;
    const d1 = new Date(eDay.getFullYear(), eDay.getMonth(), eDay.getDate());
    let memo = ev.desc || "", url = ev.url || "";
    if (url && memo.split("\n")[0].trim() === url) memo = memo.split("\n").slice(1).join("\n");
    else if (!url) { const first = memo.split("\n")[0].trim(); if (/^https?:\/\/\S+$/i.test(first)) { url = first; memo = memo.split("\n").slice(1).join("\n"); } }
    const edit = { id: ev.id, cal: ev.cal, title: ev.title === "(제목 없음)" ? "" : ev.title, date: ymd(d0), all: ev.all,
      s: hhmm(ev.s), e: hhmm(ev.e), span: Math.max(0, Math.round((d1 - d0) / 864e5)), loc: ev.loc || "", url, memo: memo.trim() };
    openGSheet(edit);
  }
  function openGSheet(edit) {
    if (!gWritable.length) return;
    edit = edit && edit.id ? edit : null;
    if (inHost && !POPUP) { host({ cmd: "popup", kind: "gevent", data: { date: selected >= today ? selected : today, token: gToken, cals: gWritable, edit } }); return; }
    gEdit = edit;
    gSelCal = edit ? edit.cal : (gWritable.find(c => c.id === gSelCal) || gWritable[0]).id;
    const now = new Date();
    $("gTitleH").textContent = edit ? "일정 수정" : "일정 추가";
    $("gOk").textContent = edit ? "저장" : "추가하기";
    $("gDel").hidden = !edit; $("gDel").classList.remove("arm"); $("gDel").textContent = "삭제";
    $("gCalFld").hidden = !!edit;
    const calName = edit ? ((gWritable.find(c => c.id === edit.cal) || {}).name || "") : "";
    $("gCalNote").hidden = !edit; $("gCalNote").textContent = edit ? `캘린더: ${calName}` : "";
    if (edit) {
      $("gDate").value = edit.date; $("gAll").checked = !!edit.all; $("gTimes").hidden = !!edit.all;
      $("gStart").value = edit.all ? "09:00" : edit.s; $("gEnd").value = edit.all ? "10:00" : edit.e;
      $("gTitle").value = edit.title; $("gLoc").value = edit.loc; $("gDesc").value = edit.memo;
      if (edit.span > 0) gCalc(`${edit.span + 1}일에 걸친 일정이에요. 날짜를 바꾸면 기간은 그대로 옮겨져요.`);
      else gCalc("");
    } else {
      $("gDate").value = selected >= today ? selected : today;
      let h0 = now.getHours() + 1; if (h0 > 22) h0 = 9;
      $("gStart").value = pad(h0) + ":00"; $("gEnd").value = pad(h0 + 1) + ":00";
      $("gAll").checked = false; $("gTimes").hidden = false;
      for (const id of ["gTitle", "gLoc", "gDesc"]) $(id).value = "";
      gCalc("");
    }
    $("gNew").hidden = true; renderGCals();
    $("gsheet").hidden = false; report();
    setTimeout(() => $("gTitle").focus(), 30);
  }
  function closeGSheet() { if (POPUP) { host({ cmd: "close" }); return; } $("gsheet").hidden = true; report(); $("gAddBtn").focus(); }
  $("gAddBtn").onclick = () => openGSheet();
  $("gOut").onclick = () => { gEvents = null; gToken = null; host({ cmd: "glogout" }); };
  $("updBtn").onclick = () => { $("updBtn").disabled = true; $("updBtn").textContent = "업데이트 중…"; host({ cmd: "update" }); };
  $("gOpen").onclick = () => host({ cmd: "open", url: "https://calendar.google.com/calendar/r" });
  $("gClose").onclick = closeGSheet; $("gCancel").onclick = closeGSheet;
  $("gsheet").addEventListener("click", e => { if (e.target === $("gsheet")) closeGSheet(); });
  document.addEventListener("keydown", e => { if (e.key === "Escape" && !$("gsheet").hidden) closeGSheet(); });
  $("gAll").addEventListener("change", () => { $("gTimes").hidden = $("gAll").checked; report(); });
  $("gStart").addEventListener("change", () => {
    const [hh, mm] = ($("gStart").value || "09:00").split(":").map(Number);
    const e = new Date(2000, 0, 1, hh + 1, mm); $("gEnd").value = hhmm(e);
  });
  const tzOff = d => { const o = -d.getTimezoneOffset(), s = o >= 0 ? "+" : "-", a = Math.abs(o); return `${s}${pad(Math.floor(a / 60))}:${pad(a % 60)}`; };
  // 폼 내용을 검사해서 일정 정보로 만든다 (오류면 문자열을 돌려줌)
  function readGForm() {
    const title = $("gTitle").value.trim(), date = $("gDate").value, all = $("gAll").checked;
    const loc = $("gLoc").value.trim(), url = gEdit ? (gEdit.url || "") : "", memo = $("gDesc").value.trim();
    if (!title) return { err: "제목을 입력하세요.", focus: "gTitle" };
    if (!date) return { err: "날짜를 선택하세요.", focus: "gDate" };
    let s = "", e = "";
    if (!all) {
      s = $("gStart").value; e = $("gEnd").value;
      if (!s || !e) return { err: "시작·종료 시간을 선택하세요.", focus: "gStart" };
      if (e <= s && !(gEdit && gEdit.span > 0)) return { err: "종료 시간이 시작 시간보다 늦어야 해요.", focus: "gEnd" };
    }
    const details = [url, memo].filter(Boolean).join("\n");
    return { title, date, all, s, e, loc, url, details };
  }
  async function copyText(t) {
    host({ cmd: "copy", text: t });
    try { await navigator.clipboard.writeText(t); } catch (e) {}
  }
  async function saveGEvent() {
    const f = readGForm();
    if (f.err) { gCalc(f.err, true); $(f.focus).focus(); return; }
    const ev = { summary: f.title };
    const span = gEdit ? gEdit.span : 0;
    if (gEdit) { ev.location = f.loc; ev.description = f.details; }   // 기존 링크(source)는 그대로 둔다
    else { if (f.loc) ev.location = f.loc; if (f.details) ev.description = f.details; }
    if (f.all) { const n = parse(f.date); n.setDate(n.getDate() + 1 + span); ev.start = { date: f.date, dateTime: null }; ev.end = { date: ymd(n), dateTime: null }; }
    else {
      const ed = parse(f.date); ed.setDate(ed.getDate() + span);
      ev.start = { dateTime: `${f.date}T${f.s}:00${tzOff(parse(f.date))}`, date: null };
      ev.end = { dateTime: `${ymd(ed)}T${f.e}:00${tzOff(ed)}`, date: null };
    }
    if (!gEdit) { if (ev.start.dateTime === null) delete ev.start.dateTime; if (ev.end.dateTime === null) delete ev.end.dateTime; if (ev.start.date === null) delete ev.start.date; if (ev.end.date === null) delete ev.end.date; }
    if (!gToken) { gPendingSave = saveGEvent; host({ cmd: "gtoken" }); gCalc("구글에 연결하는 중…"); return; }
    $("gOk").disabled = true; $("gOk").textContent = gEdit ? "저장 중…" : "추가 중…"; gCalc("");
    try {
      const cal = gEdit ? gEdit.cal : (gSelCal || "primary");
      const url = `https://www.googleapis.com/calendar/v3/calendars/${encodeURIComponent(cal)}/events` + (gEdit ? "/" + encodeURIComponent(gEdit.id) : "");
      const r = await fetch(url, {
        method: gEdit ? "PATCH" : "POST", headers: { Authorization: "Bearer " + gToken, "Content-Type": "application/json" }, body: JSON.stringify(ev)
      });
      if (r.status === 401) { gToken = null; gPendingSave = saveGEvent; host({ cmd: "gtoken", force: true }); gCalc("다시 연결하는 중…"); return; }
      if (r.status === 403) {
        let reason = ""; try { reason = JSON.stringify(await r.json()); } catch {}
        if (/insufficient|scope/i.test(reason)) {
          gCalc("일정 추가 권한이 없어요. 구글에 한 번 더 로그인해서 권한을 허용해 주세요.", true);
          $("gOk").textContent = "구글 다시 로그인"; $("gOk").disabled = false; $("gOk").dataset.relogin = "1"; return;
        }
        gCalc(gEdit ? "이 일정을 수정할 권한이 없어요." : "이 캘린더에는 일정을 추가할 수 없어요.", true); return;
      }
      if (!r.ok) throw new Error("HTTP " + r.status);
      let doneMsg = gEdit ? `${f.title} 일정을 수정했어요` : `${f.title} 일정을 추가했어요`;
      const selfIds = gEdit ? [`${gEdit.cal}|${gEdit.id}`] : [`add|${gSelCal || "primary"}|${f.title}`];
      if (POPUP) { host({ cmd: "done", msg: doneMsg, date: f.date, ids: selfIds }); return; }
      selfFrom(selfIds);
      closeGSheet(); toast(doneMsg);
      gRequest();
    } catch (e) {
      gCalc(gEdit ? "일정을 저장하지 못했어요. 잠시 후 다시 시도해 주세요." : "일정을 추가하지 못했어요. 잠시 후 다시 시도해 주세요.", true);
    } finally {
      if (!$("gOk").dataset.relogin) { $("gOk").disabled = false; $("gOk").textContent = gEdit ? "저장" : "추가하기"; }
    }
  }
  $("gDel").onclick = async () => {
    if (!gEdit) return;
    const b = $("gDel");
    if (!b.classList.contains("arm")) { b.classList.add("arm"); b.textContent = "정말 삭제"; setTimeout(() => { if (b.isConnected && b.classList.contains("arm")) { b.classList.remove("arm"); b.textContent = "삭제"; } }, 3000); return; }
    if (!gToken) { host({ cmd: "gtoken" }); gCalc("구글에 연결하는 중이에요. 다시 눌러 주세요.", true); return; }
    b.disabled = true;
    try {
      const r = await fetch(`https://www.googleapis.com/calendar/v3/calendars/${encodeURIComponent(gEdit.cal)}/events/${encodeURIComponent(gEdit.id)}`, { method: "DELETE", headers: { Authorization: "Bearer " + gToken } });
      if (r.status === 401) { host({ cmd: "gtoken", force: true }); gCalc("다시 연결했어요. 한 번 더 눌러 주세요.", true); return; }
      if (!r.ok && r.status !== 404 && r.status !== 410) throw new Error("HTTP " + r.status);
      const msgT = `${$("gTitle").value.trim() || "일정"} 일정을 삭제했어요`;
      if (POPUP) { host({ cmd: "done", msg: msgT, ids: [`${gEdit.cal}|${gEdit.id}`] }); return; }
      selfMark(gEdit.cal, gEdit.id);
      gEvents = (gEvents || []).filter(x => !(x.id === gEdit.id && x.cal === gEdit.cal));
      closeGSheet(); toast(msgT); renderAll();
    } catch (e) { gCalc("일정을 삭제하지 못했어요.", true); }
    finally { b.disabled = false; }
  };
  $("gForm").addEventListener("submit", ev => {
    ev.preventDefault();
    if ($("gOk").dataset.relogin) { delete $("gOk").dataset.relogin; $("gOk").textContent = "추가하기"; host({ cmd: "glogin" }); if (!POPUP) closeGSheet(); return; }
    saveGEvent();
  });

  // ---------------- 내 팀원 고르기 ----------------
  let tMembers = [], tPick = new Set();
  function openTeam() {
    if (!me) return;
    const list = Object.keys(members).map(id => ({ id, name: members[id] || "이름 미설정", color: colorOf(id), me: id === me.id }))
      .sort((a, b) => (b.me - a.me) || a.name.localeCompare(b.name, "ko"));
    const sel = Array.isArray(teamSel) ? teamSel : list.map(x => x.id);
    if (inHost && !POPUP) { host({ cmd: "popup", kind: "team", data: { members: list, sel, uid: me.id } }); return; }
    showTeam(list, sel);
  }
  function showTeam(list, sel) {
    tMembers = list; tPick = new Set(sel);
    renderTeam();
    $("tsheet").hidden = false; report();
    setTimeout(() => { const f = $("tList").querySelector(".trow"); if (f) f.focus(); }, 30);
  }
  function renderTeam() {
    const box = $("tList"); box.replaceChildren();
    for (const m of tMembers) {
      const on = m.me || tPick.has(m.id);
      const b = document.createElement("button"); b.type = "button"; b.className = "trow";
      b.setAttribute("role", "checkbox"); b.setAttribute("aria-checked", on ? "true" : "false");
      if (m.me) b.setAttribute("aria-disabled", "true");
      b.style.setProperty("--c", m.color);
      b.innerHTML = `<span class="bx"><svg viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="3.2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg></span><span>${esc(m.name)}</span>${m.me ? "<small>나 · 항상 표시</small>" : ""}`;
      b.onclick = () => { if (m.me) return; if (tPick.has(m.id)) tPick.delete(m.id); else tPick.add(m.id); renderTeam(); const nb = $("tList").children[tMembers.indexOf(m)]; if (nb) nb.focus(); };
      box.append(b);
    }
    const cnt = tMembers.filter(m => !m.me && tPick.has(m.id)).length, total = tMembers.filter(m => !m.me).length;
    $("tCount").textContent = `${cnt} / ${total}명`;
  }
  function closeTeam() { if (POPUP) { host({ cmd: "close" }); return; } $("tsheet").hidden = true; report(); $("teamBtn").focus(); }
  function applyTeam(ids) {
    ids = (ids || []).filter(Boolean);
    const all = Object.keys(members).filter(id => !me || id !== me.id);
    teamSel = all.length && all.every(id => ids.includes(id)) ? null : ids;
    try { localStorage.setItem("tlw.team", JSON.stringify(teamSel)); } catch (e) {}
    renderAll();
  }
  $("teamBtn").onclick = openTeam;
  $("allBtn").onclick = () => {
    showAll = !showAll;
    try { localStorage.setItem("tlw.showAll", showAll ? "1" : "0"); } catch (e) {}
    renderAll(); $("allBtn").focus();
    toast(showAll ? "모든 사람의 휴가를 보여줘요" : "내 팀원 휴가만 보여줘요");
  };
  $("tAll").onclick = () => { tMembers.forEach(m => tPick.add(m.id)); renderTeam(); };
  $("tNone").onclick = () => { tPick = new Set(); renderTeam(); };
  $("tClose").onclick = closeTeam; $("tCancel").onclick = closeTeam;
  $("tsheet").addEventListener("click", e => { if (e.target === $("tsheet")) closeTeam(); });
  document.addEventListener("keydown", e => { if (e.key === "Escape" && !$("tsheet").hidden) closeTeam(); });
  $("tForm").addEventListener("submit", ev => {
    ev.preventDefault();
    const ids = tMembers.filter(m => !m.me && tPick.has(m.id)).map(m => m.id);
    const msgT = `팀원 ${ids.length}명의 휴가를 보여줘요`;
    if (POPUP) { host({ cmd: "done", msg: msgT, ids }); return; }
    applyTeam(ids); closeTeam(); toast(msgT);
  });

  // ---------------- 팝업 창 모드 (위젯 밖에 떠 있는 별도 창) ----------------
  function initPopup(kind, data) {
    data = data || {};
    selected = data.date || today;
    if (kind === "leave") {
      me = { id: data.uid }; leaves = Array.isArray(data.mine) ? data.mine : [];
      if (window.supabase) sb = window.supabase.createClient(CFG.URL, CFG.KEY, { auth: { persistSession: true, autoRefreshToken: true, storageKey: "team-leave-auth" } });
      openSheet();
      if (!sb) { const o = $("sCalc"); o.textContent = "팀 휴가 서버에 연결하지 못했어요."; o.className = "calc err"; $("sOk").disabled = true; }
    } else if (kind === "gevent") {
      gToken = data.token || null; gWritable = Array.isArray(data.cals) ? data.cals : [];
      openGSheet(data.edit || null);
    } else if (kind === "settings") {
      showSettings(data.ui || data, data.host || {});
    } else if (kind === "team") {
      me = { id: data.uid };
      showTeam(Array.isArray(data.members) ? data.members : [], Array.isArray(data.sel) ? data.sel : (data.sel ? [data.sel] : []));
    }
  }
  // ======================= 설정 창 =======================
  const PRIVACY_URL = "https://none-hongcheol.github.io/TeamCal/privacy.html";
  const HOME_URL = "https://none-hongcheol.github.io/TeamCal/";
  function openSettings() {
    const prim = gCals.find(c => c.primary);
    const ui = {
      gEmail: prim ? prim.id : "", teamName: me && members ? (members[me.id] || "") : "", teamOn: !!me,
      showAll, hasTeam: Array.isArray(teamSel), hint: lsGet("tlw.hintOff") !== "1",
      ntOn: lsGet("tlw.ntOn") !== "0", ntWin: lsGet("tlw.ntWin") !== "0",
      dlCals: gmode === "google" ? dlEligible().map(c => ({ id: c.id, name: c.name.replace(/ \(기본\)$/, ""), color: c.color || "", on: dlOn(c), has: !!dlData[c.id] })) : []
    };
    if (inHost && !POPUP) { host({ cmd: "popup", kind: "settings", data: ui }); return; }
    showSettings(ui, {});
  }
  let setUi = {}, setHost = {}, setTab = "일반";
  const SET_TABS = ["일반", "캘린더", "팀 휴가", "알림", "정보"];
  function showSettings(ui, hs) {
    setUi = ui || {}; setHost = hs || {};
    $("setVer").textContent = setHost.version ? "TeamCal " + setHost.version : "";
    renderSettings(); $("setsheet").hidden = false; report();
  }
  function sset(key, value) { host({ cmd: "set", key, value }); }
  function uiset(key, value) { setUi[key] = value; host({ cmd: "set", key: "ui", value: { key, value } }); }
  function renderSettings() {
    const tabs = $("setTabs");
    tabs.innerHTML = SET_TABS.map(t => `<button type="button" role="tab" aria-selected="${t === setTab}" data-tab="${t}">${t}</button>`).join("");
    tabs.querySelectorAll("[data-tab]").forEach(b => b.onclick = () => { setTab = b.dataset.tab; renderSettings(); const nb = $("setTabs").querySelector(`[data-tab="${setTab}"]`); if (nb) nb.focus(); });
    const sw = (id, on, label, sub) => `<div class="srow"><div class="st" id="l_${id}">${label}${sub ? `<small>${sub}</small>` : ""}</div><button type="button" class="ssw" role="switch" aria-labelledby="l_${id}" aria-checked="${!!on}" data-sw="${id}"></button></div>`;
    const seg = (id, val, opts, label) => `<div class="srow"><div class="st" id="l_${id}">${label}</div><div class="sseg" role="radiogroup" aria-labelledby="l_${id}">${opts.map(([v, t]) => `<button type="button" role="radio" aria-checked="${String(v) === String(val)}" data-seg="${id}" data-v="${v}">${t}</button>`).join("")}</div></div>`;
    const btn = (label, sub, act, txt, cls) => `<div class="srow"><div class="st">${label}${sub ? `<small>${sub}</small>` : ""}</div><button type="button" class="sbtn ${cls || ""}" data-act="${act}">${txt}</button></div>`;
    const H = setHost, U = setUi;
    let h = "";
    if (setTab === "일반") {
      const op = Math.round((+H.opacity || 1) * 100);
      h += `<div class="sgrp">화면</div>` + seg("theme", H.theme === "dark" ? "dark" : "light", [["light", "라이트"], ["dark", "다크"]], "테마")
        + `<div class="srow"><div class="st" id="l_op">투명도</div><div class="srange"><input type="range" min="50" max="100" step="10" value="${op}" aria-labelledby="l_op" id="setOp"><em id="setOpV">${op}%</em></div></div>`
        + sw("hover", H.hover, "마우스를 올리면 선명하게", "투명할 때 마우스를 올리면 잠깐 100%로")
        + sw("top", H.top, "항상 위에 표시")
        + seg("size", String(H.size || 1), [["0.9", "작게"], ["1", "보통"], ["1.15", "크게"]], "글자 크기")
        + `<div class="sgrp">시작 · 위치</div>` + sw("autostart", H.autostart, "Windows 시작 시 자동 실행")
        + btn("위젯 위치와 크기", "화면 밖으로 사라졌을 때", "resetPos", "처음 위치로");
    } else if (setTab === "캘린더") {
      h += `<div class="sgrp">구글 계정</div>`;
      if (H.gmode === "google") h += `<div class="sacct"><div class="av">G</div><div class="st">구글 캘린더 연결됨<small>${esc(U.gEmail || "")}</small></div><button type="button" class="sbtn" data-act="glogout">연결 해제</button></div>`;
      else if (H.gmode === "ical") h += `<div class="sacct"><div class="av">i</div><div class="st">iCal 주소로 연결됨<small>보기 전용</small></div><button type="button" class="sbtn" data-act="glogout">연결 해제</button></div>`;
      else h += `<div class="sacct"><div class="av" style="background:var(--dot)">?</div><div class="st">연결 안 됨<small>구글 계정을 연결하면 내 일정이 보여요</small></div><button type="button" class="sbtn pri" data-act="glogin">구글 로그인</button></div>`;
      h += sw("autoLogin", H.autoLogin, "자동 로그인", "위젯을 다시 켜도 바로 연결")
        + (Array.isArray(U.dlCals) && U.dlCals.length ? `<div class="sgrp">데드라인 (캘린더의 마지막 일정까지 D-day)</div>` + U.dlCals.map((c, i) =>
            `<div class="srow"><div class="st" id="l_dl${i}"><span style="display:inline-block;width:8px;height:8px;border-radius:50%;background:${esc(c.color || "var(--accent)")};margin-right:6px"></span>${esc(c.name)}${c.has ? "" : "<small>앞으로의 일정이 없어요</small>"}</div><button type="button" class="ssw" role="switch" aria-labelledby="l_dl${i}" aria-checked="${!!c.on}" data-dlsw="${esc(c.id)}"></button></div>`).join("") : "")
        + `<div class="sgrp">팀 캘린더 보는 법</div><div class="srow"><div class="st">1. 팀 그룹에 가입하세요<small>2. 가입 후 프로젝트 캘린더 공유 링크를 PM에게 요청하세요. 링크를 열고 [추가]를 누르면 위젯에 자동으로 보여요.</small></div><button type="button" class="sbtn" data-act="group">그룹 열기 ↗</button></div>`
        + `<div class="sgrp">기타</div><div class="sbtns"><button type="button" class="sbtn" data-act="gweb">구글 캘린더 열기 ↗</button>${H.gmode === "google" ? "" : `<button type="button" class="sbtn" data-act="gical">iCal 주소로 연결…</button>`}<button type="button" class="sbtn" data-act="gguide">설정 방법 보기</button></div>`;
    } else if (setTab === "팀 휴가") {
      h += `<div class="sgrp">로그인</div>`;
      h += U.teamOn ? `<div class="sacct"><div class="av">${esc((U.teamName || "?").slice(0, 1))}</div><div class="st">${esc(U.teamName || "로그인됨")}<small>팀 휴가 사이트와 같은 계정</small></div><button type="button" class="sbtn" data-act="teamLogout">로그아웃</button></div>`
        : `<div class="sacct"><div class="av" style="background:var(--dot)">?</div><div class="st">로그인 안 됨<small>위젯 화면에서 이름·PIN으로 로그인해요</small></div></div>`;
      h += `<div class="sgrp">보기</div>` + btn("내 팀원", "같이 일하는 사람만 골라 보기", "teamPick", "고르기…")
        + (U.hasTeam ? sw("showAll", U.showAll, "팀 밖 사람 휴가도 보기", "내 팀원이 아닌 사람은 점선으로") : "")
        + btn("팀 휴가 사이트", "", "teamSite", "열기 ↗");
    } else if (setTab === "알림") {
      h += `<div class="sgrp">캘린더 변경 알림</div>` + sw("ntOn", U.ntOn, "다른 사람이 캘린더를 바꾸면 알림", "공유 캘린더의 앞으로 2주 일정")
        + sw("ntWin", U.ntWin, "Windows 알림도 띄우기", "위젯을 숨겨 두거나 다른 창을 쓸 때")
        + `<div class="sgrp">업데이트</div>` + btn("새 버전 확인", "켤 때 · 30분마다 자동으로 확인해요", "update", "지금 확인");
    } else {
      h += `<div class="sgrp">TeamCal</div><div class="srow"><div class="st">버전<small>팀 휴가 + 내 일정 위젯</small></div><span style="font-size:12.5px;font-weight:600">${esc(H.version || "")}</span></div>`
        + btn("업데이트", "", "update", "확인")
        + btn("홈페이지", "", "home", "열기 ↗") + btn("개인정보처리방침", "", "privacy", "열기 ↗")
        + `<div class="sgrp">제거</div>` + btn("TeamCal 제거", "설정·로그인 정보가 지워져요", "uninstall", "제거…", "dng");
    }
    const body = $("setBody"); body.innerHTML = h;
    body.querySelectorAll("[data-sw]").forEach(b => b.onclick = () => {
      const k = b.dataset.sw, on = b.getAttribute("aria-checked") !== "true";
      b.setAttribute("aria-checked", on ? "true" : "false");
      if (["hint", "ntOn", "ntWin", "showAll"].includes(k)) uiset(k, on); else { setHost[k] = on; sset(k, on); }
    });
    body.querySelectorAll("[data-dlsw]").forEach(b => b.onclick = () => {
      const on = b.getAttribute("aria-checked") !== "true"; b.setAttribute("aria-checked", on ? "true" : "false");
      const c = (setUi.dlCals || []).find(x => x.id === b.dataset.dlsw); if (c) c.on = on;
      host({ cmd: "set", key: "ui", value: { key: "dl:" + b.dataset.dlsw, value: on } });
    });
    body.querySelectorAll("[data-seg]").forEach(b => b.onclick = () => {
      const k = b.dataset.seg, v = b.dataset.v;
      b.parentElement.querySelectorAll("button").forEach(x => x.setAttribute("aria-checked", x === b ? "true" : "false"));
      setHost[k] = k === "size" ? +v : v; sset(k, k === "size" ? +v : v);
    });
    const op = body.querySelector("#setOp");
    if (op) { op.oninput = () => { $("setOpV").textContent = op.value + "%"; }; op.onchange = () => { setHost.opacity = +op.value / 100; sset("opacity", +op.value / 100); }; }
    body.querySelectorAll("[data-act]").forEach(b => b.onclick = () => {
      const a = b.dataset.act;
      const urls = { gweb: "https://calendar.google.com/calendar/r", home: HOME_URL, privacy: PRIVACY_URL, group: TEAM_GROUP };
      if (urls[a]) { host({ cmd: "open", url: urls[a] }); return; }
      if (a === "glogout") { setHost.gmode = ""; renderSettings(); }
      if (a === "teamLogout") { setUi.teamOn = false; renderSettings(); }
      host({ cmd: "set", key: "act", value: a });
    });
    report();
  }
  $("setClose").onclick = () => { if (POPUP) host({ cmd: "close" }); else { $("setsheet").hidden = true; report(); } };
  document.addEventListener("keydown", e => { if (e.key === "Escape" && !$("setsheet").hidden) $("setClose").click(); });

  // ======================= 호스트 메시지 =======================
  function applyTheme(t) { document.body.dataset.theme = t === "dark" ? "dark" : "light"; if (!POPUP) renderAll(); }
  if (inHost) window.chrome.webview.addEventListener("message", ev => {
    const m = ev.data || {};
    if (POPUP) {
      if (m.type === "popup") { applyTheme(m.theme); initPopup(m.kind, m.data); }
      else if (m.type === "theme") { applyTheme(m.theme); if (!$("setsheet").hidden) { setHost.theme = m.theme; renderSettings(); } }
      else if (m.type === "settings" && !$("setsheet").hidden) { setHost = m.host || setHost; if (m.ui) setUi = Object.assign(setUi, m.ui); renderSettings(); }
      else if (m.type === "gtoken" && m.token) { gToken = m.token; if (gPendingSave) { const f = gPendingSave; gPendingSave = null; f(); } }
      return;
    }
    switch (m.type) {
      case "update":
        $("upd").hidden = false; $("updBtn").disabled = false; $("updBtn").textContent = "업데이트";
        $("updText").textContent = m.error ? m.error : `새 버전 ${m.version}${m.notes ? " · " + m.notes : ""}`;
        report(); break;
      case "updating": $("upd").hidden = false; $("updBtn").disabled = true; $("updBtn").textContent = "업데이트 중…"; break;
      case "openTeam": openTeam(); break;
      case "openSettings": openSettings(); break;
      case "uipref": {
        const k = m.key, v = !!m.value;
        if (String(k).startsWith("dl:")) setDlOn(String(k).slice(3), v);
        else if (k === "hint") { lsSet("tlw.hintOff", v ? null : "1"); renderG(); }
        else if (k === "ntOn") lsSet("tlw.ntOn", v ? null : "0");
        else if (k === "ntWin") lsSet("tlw.ntWin", v ? null : "0");
        else if (k === "showAll") { showAll = v; try { localStorage.setItem("tlw.showAll", v ? "1" : "0"); } catch (e) {} renderAll(); }
        break;
      }
      case "teamcal": setTeamCal(m.cfg); break;
      case "tcshow": lsSet("tlw.hintOff", null); renderG(); break;
      case "popupDone":
        toast(m.msg || "완료했어요");
        if (m.kind === "team") { applyTeam(Array.isArray(m.ids) ? m.ids : (m.ids ? [m.ids] : [])); break; }
        if (m.kind === "leave") { if (m.date) { selected = m.date; const sd = parse(m.date); view = new Date(sd.getFullYear(), sd.getMonth(), 1); } reload(); }
        else { if (m.kind === "gevent") selfFrom(Array.isArray(m.ids) ? m.ids : (m.ids ? [m.ids] : [])); gRequest(); }
        break;
      case "config":
        applyTheme(m.theme);
        document.body.classList.toggle("fixed", !!m.fixed); if (m.maxH) maxPhys = +m.maxH; lastH = 0; report();
        $("bPin").classList.toggle("on", !!m.pinned);
        if (typeof m.autoLogin === "boolean") gAutoLogin = m.autoLogin;
        if (m.gmode !== gmode) { gmode = m.gmode || ""; gEvents = null; gStatus = ""; gRequest(); }
        break;
      case "theme": applyTheme(m.theme); break;
      case "fixed": document.body.classList.toggle("fixed", !!m.on); if (m.maxH) maxPhys = +m.maxH; lastH = 0; report(); break;
      case "pinned": $("bPin").classList.toggle("on", !!m.on); break;
      case "gmode": gmode = m.gmode || ""; gEvents = null; gStatus = ""; gRequest(); break;
      case "gstatus": gStatus = m.status || ""; if (m.status === "waiting") { gEvents = null; gError = ""; } renderG(); break;
      case "gtoken": gStatus = ""; onToken(m); break;
      case "ics": if (m.text) { try { loadIcs(m.text); } catch (e) { gError = "iCal 일정을 읽지 못했어요."; renderG(); } } else { gError = m.error || "iCal 주소에서 일정을 받지 못했어요."; renderG(); } break;
      case "refresh": reload(); gRequest(); break;
      case "logout": if (sb) sb.auth.signOut(); break;
    }
  });
  $("bOpa").onclick = () => host({ cmd: "opacity" });
  $("bPin").onclick = () => host({ cmd: "pin" });
  $("bMenu").onclick = openSettings;
  $("bHide").onclick = () => host({ cmd: "minimize" });
  $("bTray").onclick = () => host({ cmd: "hide" });
  // app-region 미지원 런타임용: 머리글을 끌면 창 이동
  $("hd").addEventListener("mousedown", e => { if (e.button === 0 && !e.target.closest("button")) host({ cmd: "drag" }); });
  document.querySelectorAll(".grab, .dh").forEach(el => el.addEventListener("mousedown", e => {
    if (POPUP && e.button === 0 && !e.target.closest("button")) host({ cmd: "drag" });
  }));

  // 가장자리를 끌어서 크기 조절
  document.querySelectorAll(".rz").forEach(el => el.addEventListener("mousedown", e => {
    if (e.button === 0) { e.preventDefault(); host({ cmd: "resize", hit: +el.dataset.hit }); }
  }));
  // 창 높이를 내용에 맞추기 (사용자가 크기를 정하면 고정 + 스크롤)
  let lastH = 0, lastWide = null, wideT;
  // 창 너비가 바뀌어 넓은/좁은 달력이 바뀌면 다시 그림
  window.addEventListener("resize", () => {
    clearTimeout(wideT);
    wideT = setTimeout(() => {
      if (POPUP || !me || $("calWrap").hidden) return;
      const w = ($("grid").clientWidth || 0) / 7 >= 70;
      if (w !== lastWide || w) renderGrid();
    }, 120);
  });
  function report() {
    if (POPUP) {
      const f = !$("sheet").hidden ? $("sForm") : (!$("gsheet").hidden ? $("gForm") : (!$("tsheet").hidden ? $("tForm") : (!$("setsheet").hidden ? $("setForm") : null)));
      if (!f) return;
      const h = Math.ceil(f.getBoundingClientRect().height * window.devicePixelRatio);
      if (h !== lastH) { lastH = h; host({ cmd: "size", h }); }
      return;
    }
    const card = $("card");
    fitUp();
    const open = !$("sheet").hidden ? $("sForm") : (!$("gsheet").hidden ? $("gForm") : (!$("tsheet").hidden ? $("tForm") : null));
    card.style.minHeight = open ? Math.ceil(open.getBoundingClientRect().height + 120) + "px" : "";
    const h = Math.ceil(card.getBoundingClientRect().height * window.devicePixelRatio);
    if (h !== lastH) { lastH = h; host({ cmd: "size", h }); }
  }
  // 위젯이 화면(또는 정해 둔 높이)을 넘으면, 다가오는 일정 목록만 스크롤되게 높이를 줄인다
  let maxPhys = 0;
  function fitUp() {
    const up = $("gUp"); if (!up || POPUP) return;
    if (!$("sheet").hidden || !$("gsheet").hidden || !$("tsheet").hidden) { if (up.style.maxHeight) up.style.maxHeight = ""; return; }
    // 정해 둔 높이(없으면 화면 높이)까지만 늘어나고, 넘치면 다가오는 일정 목록 안에서만 스크롤
    const avail = maxPhys ? maxPhys / window.devicePixelRatio : (screen.availHeight - 24);
    const yr = document.querySelector(".yr");
    const bottom = yr.getBoundingClientRect().bottom + (document.scrollingElement.scrollTop || 0) + 18;   // 내용 끝 (카드 아래 여백 포함)
    const over = bottom - avail;
    const cur = up.clientHeight, full = up.scrollHeight;
    let want = Math.round(cur - over);
    if (want >= full) { if (up.style.maxHeight) up.style.maxHeight = ""; }
    else { want = want < 40 ? 0 : want; if (Math.abs(want - cur) > 1) up.style.maxHeight = want + "px"; }
    upFade();
  }
  function upFade() { const up = $("gUp"); if (up) up.classList.toggle("fade", up.scrollHeight - up.scrollTop - up.clientHeight > 4); }
  new ResizeObserver(report).observe($("card"));
  window.addEventListener("resize", () => { lastH = 0; report(); });

  // 날짜가 바뀌면 갱신, 구글 일정은 5분마다 + 위젯을 다시 볼 때(1분에 한 번까지)
  setInterval(() => { const t = ymd(new Date()); if (t !== today) { if (selected === today) selected = t; today = t; renderAll(); } }, 60 * 1000);
  if (!POPUP) {
    $("bRefresh").onclick = manualRefresh;
    setInterval(rfLabel, 30 * 1000);
    setInterval(() => { if (gmode && Date.now() - gLastReq > 60 * 1000) gRequest(); }, 5 * 60 * 1000);
    const refreshSoon = () => { if (gmode && gEvents && Date.now() - gLastReq > 60 * 1000) gRequest(); };
    window.addEventListener("focus", refreshSoon);
    document.addEventListener("visibilitychange", () => { if (!document.hidden) refreshSoon(); });
  }

  if (POPUP) { document.body.classList.add("popup"); new ResizeObserver(report).observe($("sForm")); new ResizeObserver(report).observe($("gForm")); new ResizeObserver(report).observe($("tForm")); }
  else { renderHeader(); renderG(); initSupabase(); }
  host({ cmd: "ready" });
  window.__tlw = { applyTheme, loadIcs, onToken, openGSheet, initPopup, readGForm, openInvite, setTeamCal, setG: g => { gmode = g; renderG(); }, state: () => ({ gEvents, leaves, members }) };
})();
</script>
</body>
</html>
'@

$GuideText = @'
======================================================
 TeamCal - 구글 캘린더 연결 방법 (처음 한 번, 약 10분)
======================================================

위젯이 내 구글 캘린더를 보고, 위젯에서 일정을 추가할 수 있도록 허락하는 설정입니다.
구글 클라우드 사용은 무료이며, 결제 정보는 필요 없습니다.

------------------------------------------------------
1. 프로젝트 만들기
------------------------------------------------------
  - https://console.cloud.google.com 에 구글 계정으로 접속합니다.
  - 화면 위쪽의 프로젝트 선택 상자 → [새 프로젝트]
  - 프로젝트 이름: 팀휴가위젯 (아무 이름이나 괜찮아요) → [만들기]
  - 만들어지면 위쪽 프로젝트 선택 상자에서 방금 만든 프로젝트를 선택합니다.

------------------------------------------------------
2. Google Calendar API 켜기
------------------------------------------------------
  - 위쪽 검색창에 "Google Calendar API" 검색 → 선택 → [사용]

------------------------------------------------------
3. OAuth 동의 화면 (Google 인증 플랫폼) 만들기
------------------------------------------------------
  - 왼쪽 메뉴 [API 및 서비스] → [OAuth 동의 화면]
    (화면에 "Google 인증 플랫폼"이라고 나오면 [시작하기])
  - 앱 이름: TeamCal
  - 사용자 지원 이메일: 내 이메일
  - 대상: [외부]
  - 연락처 정보: 내 이메일
  - 약관 동의 체크 → [만들기]

------------------------------------------------------
4. 앱 게시 (중요: 안 하면 7일마다 다시 로그인해야 해요)
------------------------------------------------------
  - 왼쪽 [대상] 메뉴 → 게시 상태 "테스트" 옆의 [앱 게시]
  - 확인 창에서 [확인] → 상태가 "프로덕션 단계"로 바뀌면 완료
  - 구글 검토(인증)는 받을 필요 없어요. 나와 팀원 몇 명이 쓰는 건 문제없습니다.

------------------------------------------------------
5. 데스크톱 앱 클라이언트 만들고 JSON 받기
------------------------------------------------------
  - 왼쪽 [클라이언트] 메뉴 → [클라이언트 만들기]
  - 애플리케이션 유형: [데스크톱 앱]   ← 꼭 "데스크톱 앱"
  - 이름: TeamCal → [만들기]
  - 만들어진 창에서 [JSON 다운로드] 를 누릅니다.
    (창을 닫았다면 클라이언트 목록에서 이름을 눌러 다시 받을 수 있어요)
  - "client_secret_....json" 파일이 다운로드 폴더에 저장됩니다.

------------------------------------------------------
6. 위젯에서 연결
------------------------------------------------------
  - 위젯의 "내 일정" 칸에서 [구글 로그인] → [예(설정 파일 불러오기)]
  - 5단계에서 받은 JSON 파일을 선택합니다.
  - 평소 쓰는 브라우저에 구글 로그인 창이 열립니다.
  - "Google에서 확인하지 않은 앱" 경고가 나오면:
      [고급] → [TeamCal(으)로 이동(안전하지 않음)]
    (내가 직접 만든 앱이라 나오는 경고예요)
  - 나오는 권한(캘린더 보기 / 일정 보기 및 수정 / 보조 캘린더 만들기)에 모두 체크하고 [계속]
    (수정·만들기 권한은 위젯에서 "+ 일정"으로 일정을 추가하거나 새 캘린더를 만들 때 쓰여요)
  - "구글 연결이 끝났어요" 화면이 나오면 브라우저 창은 닫아도 됩니다.

------------------------------------------------------
참고
------------------------------------------------------
  - 위젯은 캘린더 목록과 일정을 읽고, 내가 "+ 일정"으로 추가한 일정과
    위젯에서 만든 캘린더만 씁니다. (기존 일정·캘린더를 수정하거나 지우지 않아요)
  - 로그인 정보는 이 PC의 내 Windows 계정으로 암호화해서 저장됩니다.
  - 회사 구글 계정(Google Workspace)은 관리자가 이런 앱을 막아둔 경우가 있어요.
    그때는 메뉴(⋯) → 내 일정 → [iCal 주소로 연결] 을 쓰세요.
  - 같은 JSON 파일을 팀원에게 주면 팀원도 1~5단계 없이 6단계만 하면 됩니다.
    (팀원은 4단계 덕분에 별도 등록 없이 로그인할 수 있어요)
  - 연결을 끊으려면: 메뉴(⋯) → 내 일정 → [연결 해제]
    구글 쪽 권한까지 지우려면 https://myaccount.google.com/permissions 에서 삭제하세요.
'@

$LoginDoneHtml = @'
<!doctype html><html lang="ko"><head><meta charset="utf-8"><title>TeamCal</title>
<style>body{margin:0;height:100vh;display:grid;place-items:center;font:15px "Malgun Gothic",sans-serif;background:#fbfaf7;color:#1b1b1d}
div{text-align:center;line-height:1.8}b{font-size:20px}</style></head>
<body><div><b>구글 연결이 끝났어요</b><br>이 창은 닫아도 돼요. TeamCal에 내 일정이 표시됩니다.</div></body></html>
'@

# ======================= 설치 · 제거 공통 =======================
$UninstVbs  = Join-Path $AppDir 'uninstall.vbs'
$IconFile   = Join-Path $AppDir 'TeamCal.ico'
$NoAutoFlag = Join-Path $AppDir 'noautostart.flag'
$UninstKey  = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\TeamCal'

function New-AppBitmap([int]$n) {
    $bmp = New-Object System.Drawing.Bitmap $n, $n
    $gr = [System.Drawing.Graphics]::FromImage($bmp)
    $gr.SmoothingMode = 'AntiAlias'
    $gr.FillEllipse((New-Object System.Drawing.SolidBrush ([System.Drawing.ColorTranslator]::FromHtml('#1b1b1d'))), 0, 0, $n, $n)
    $dotW = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(235, 235, 230))
    $dotA = New-Object System.Drawing.SolidBrush ([System.Drawing.ColorTranslator]::FromHtml('#ff8a4c'))
    $k = $n / 32.0
    for ($r = 0; $r -lt 3; $r++) { for ($c = 0; $c -lt 3; $c++) {
        $b = if ($r -eq 1 -and $c -eq 2) { $dotA } else { $dotW }
        $gr.FillEllipse($b, [float]((7 + $c * 7) * $k), [float]((7 + $r * 7) * $k), [float](5 * $k), [float](5 * $k)) } }
    $gr.Dispose()
    return $bmp
}
function Save-AppIcon {
    # PNG 를 담은 .ico (바로가기·제어판 아이콘용)
    try {
        $bmp = New-AppBitmap 64
        $ms = New-Object System.IO.MemoryStream
        $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
        $png = $ms.ToArray()
        $fs = [IO.File]::Create($IconFile); $bw = New-Object System.IO.BinaryWriter($fs)
        $bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]1)
        $bw.Write([byte]64); $bw.Write([byte]64); $bw.Write([byte]0); $bw.Write([byte]0)
        $bw.Write([uint16]1); $bw.Write([uint16]32); $bw.Write([uint32]$png.Length); $bw.Write([uint32]22)
        $bw.Write($png); $bw.Close()
    } catch { Write-Log "icon: $($_.Exception.Message)" }
}
function New-Shortcut($path) {
    $ws  = New-Object -ComObject WScript.Shell
    $lnk = $ws.CreateShortcut($path)
    $lnk.TargetPath       = "$env:SystemRoot\System32\wscript.exe"
    $lnk.Arguments        = "`"$Launcher`""
    $lnk.WorkingDirectory = $AppDir
    $lnk.IconLocation     = if (Test-Path $IconFile) { "$IconFile,0" } else { "$env:SystemRoot\System32\shell32.dll,165" }
    $lnk.Description      = $AppName
    $lnk.Save()
}
function Write-Launchers {
    # 경로에 한글 사용자 이름이 있어도 되도록 환경 변수로 경로를 만든다 (파일은 ASCII)
    @'
Set sh = CreateObject("WScript.Shell")
p = sh.ExpandEnvironmentStrings("%LOCALAPPDATA%") & "\TeamLeaveWidget\TeamLeaveWidget.ps1"
sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File """ & p & """", 0, False
'@ | Set-Content -LiteralPath $Launcher -Encoding ASCII
    @'
Set sh = CreateObject("WScript.Shell")
p = sh.ExpandEnvironmentStrings("%LOCALAPPDATA%") & "\TeamLeaveWidget\TeamLeaveWidget.ps1"
sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File """ & p & """ -Uninstall", 0, False
'@ | Set-Content -LiteralPath $UninstVbs -Encoding ASCII
}
function Register-App {
    # 제어판 > 프로그램 및 기능 (설정 > 앱) 에 표시
    try {
        New-Item -Path $UninstKey -Force | Out-Null
        $size = 0; try { $size = [int]((Get-ChildItem -LiteralPath $AppDir -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum / 1KB) } catch { }
        $props = @{
            DisplayName = $AppName; DisplayVersion = $AppVersion; Publisher = 'TeamCal'
            InstallLocation = $AppDir; DisplayIcon = $IconFile
            UninstallString = "`"$env:SystemRoot\System32\wscript.exe`" `"$UninstVbs`""
            QuietUninstallString = "`"$env:SystemRoot\System32\wscript.exe`" `"$UninstVbs`""
            URLInfoAbout = 'https://none-hongcheol.github.io/TeamCal/'
            InstallDate = (Get-Date -Format 'yyyyMMdd')
        }
        foreach ($k in $props.Keys) { Set-ItemProperty -Path $UninstKey -Name $k -Value ([string]$props[$k]) }
        foreach ($k in @('NoModify', 'NoRepair')) { New-ItemProperty -Path $UninstKey -Name $k -Value 1 -PropertyType DWord -Force | Out-Null }
        New-ItemProperty -Path $UninstKey -Name 'EstimatedSize' -Value $size -PropertyType DWord -Force | Out-Null
    } catch { Write-Log "register: $($_.Exception.Message)" }
}
function Stop-OtherInstances {
    try {
        Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction Stop |
            Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -like '*TeamLeaveWidget.ps1*' -and $_.CommandLine -notlike '*-Uninstall*' -and $_.CommandLine -notlike '*-Setup*' } |
            ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    } catch { }
    Start-Sleep -Milliseconds 900
}
function Remove-AllShortcuts {
    $links = @($StartupLnk, $DesktopLnk)
    foreach ($on in $OldNames) { foreach ($dir in @([Environment]::GetFolderPath('Startup'), [Environment]::GetFolderPath('Desktop'))) { $links += (Join-Path $dir "$on.lnk") } }
    foreach ($l in $links) { Remove-Item -LiteralPath $l -Force -ErrorAction SilentlyContinue }
}

# ----------------------- 제거 (-Uninstall) -----------------------
function Invoke-Uninstall {
    [System.Windows.Forms.Application]::EnableVisualStyles()
    $q = [System.Windows.Forms.MessageBox]::Show("TeamCal 을 이 PC에서 제거할까요?`n`n· 바탕화면·시작 프로그램 바로가기`n· 프로그램과 설정, 저장된 로그인 정보`n· 구글 캘린더 연결 (구글 쪽 권한도 해제)`n`n팀 휴가 데이터와 구글 캘린더 일정은 서버에 그대로 남아요.", "$AppName 제거", 'YesNo', 'Warning', 'Button2')
    if ($q -ne 'Yes') { return }
    Stop-OtherInstances
    # 구글 쪽 로그인 해제
    $tf = Join-Path $AppDir 'google_token.dat'
    if (Test-Path $tf) {
        try {
            $sec = ConvertTo-SecureString (Get-Content $tf -Raw).Trim()
            $b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
            $rt = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b); [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b)
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri 'https://oauth2.googleapis.com/revoke' -Method Post -Body @{ token = $rt } -UseBasicParsing -TimeoutSec 6 | Out-Null
        } catch { }
    }
    Remove-AllShortcuts
    Remove-Item -Path $UninstKey -Recurse -Force -ErrorAction SilentlyContinue
    # 프로그램 폴더는 이 창이 닫힌 뒤 지운다
    $cmd = Join-Path $env:TEMP 'TeamCal_uninstall.cmd'
    $body = "@echo off`r`nchcp 65001 >nul`r`ntimeout /t 2 /nobreak >nul`r`n" +
            "for /l %%i in (1,1,15) do (`r`n  if exist `"$AppDir`" ( rmdir /s /q `"$AppDir`" 2>nul & timeout /t 2 /nobreak >nul )`r`n)`r`n" +
            "del `"%~f0`"`r`n"
    [IO.File]::WriteAllText($cmd, $body, (New-Object System.Text.UTF8Encoding($false)))
    Start-Process "$env:SystemRoot\System32\cmd.exe" -ArgumentList "/c `"$cmd`"" -WindowStyle Hidden
    [System.Windows.Forms.MessageBox]::Show("TeamCal 을 제거했어요. 남은 파일은 몇 초 안에 자동으로 정리돼요.", "$AppName 제거", 'OK', 'Information') | Out-Null
}

# ----------------------- 설치 마법사 (-Setup) -----------------------
function Install-App([bool]$desk, [bool]$auto) {
    New-Item -ItemType Directory -Force -Path $AppDir | Out-Null
    Stop-OtherInstances
    if ($PSCommandPath -ne $Installed) { Copy-Item -LiteralPath $PSCommandPath -Destination $Installed -Force }
    Write-Launchers
    Save-AppIcon
    foreach ($on in $OldNames) { foreach ($dir in @([Environment]::GetFolderPath('Startup'), [Environment]::GetFolderPath('Desktop'))) { Remove-Item -LiteralPath (Join-Path $dir "$on.lnk") -Force -ErrorAction SilentlyContinue } }
    if ($desk) { New-Shortcut $DesktopLnk } else { Remove-Item -LiteralPath $DesktopLnk -Force -ErrorAction SilentlyContinue }
    if ($auto) { Remove-Item -LiteralPath $NoAutoFlag -Force -ErrorAction SilentlyContinue; New-Shortcut $StartupLnk }
    else { Set-Content -LiteralPath $NoAutoFlag 'off'; Remove-Item -LiteralPath $StartupLnk -Force -ErrorAction SilentlyContinue }
    # 같은 폴더(또는 exe 안)에 구글 클라우드 설정 파일이 있으면 같이 넣기
    $here = Split-Path -Parent $PSCommandPath
    $cj = @(Get-ChildItem -LiteralPath $here -Filter '*.json' -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq 'google_client.json' -or $_.Name -like 'client_secret*.json' }) | Select-Object -First 1
    if ($cj) {
        try {
            $j = Get-Content -LiteralPath $cj.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($j.installed -and $j.installed.client_id) { Copy-Item -LiteralPath $cj.FullName -Destination (Join-Path $AppDir 'google_client.json') -Force }
        } catch { Write-Log "client json: $($_.Exception.Message)" }
    }
    Register-App
}
function Show-Setup {
    # exe(IExpress)가 관리자 권한으로 띄운 경우: 로그인한 사용자 권한으로 다시 실행 (사용자 폴더에 설치하기 위해)
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    $pubDir = Join-Path $env:PUBLIC 'TeamCal_setup'
    if ($isAdmin -and -not ($PSCommandPath -like "$pubDir*")) {
        try {
            $pub = Join-Path $env:PUBLIC 'TeamCal_setup'
            New-Item -ItemType Directory -Force -Path $pub | Out-Null
            $here = Split-Path -Parent $PSCommandPath
            Get-ChildItem -LiteralPath $here -File | Where-Object { $_.Name -eq 'TeamLeaveWidget.ps1' -or $_.Name -like '*.json' } | Copy-Item -Destination $pub -Force
            @'
Set sh = CreateObject("WScript.Shell")
p = sh.ExpandEnvironmentStrings("%PUBLIC%") & "\TeamCal_setup\TeamLeaveWidget.ps1"
sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File """ & p & """ -Setup", 0, False
'@ | Set-Content -LiteralPath (Join-Path $pub 'setup.vbs') -Encoding ASCII
            Start-Process "$env:SystemRoot\explorer.exe" -ArgumentList "`"$(Join-Path $pub 'setup.vbs')`""
            return
        } catch { Write-Log "setup redirect: $($_.Exception.Message)" }
    }
    try { Add-Type -Namespace TLWS -Name Dpi -MemberDefinition '[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool SetProcessDPIAware();'; [TLWS.Dpi]::SetProcessDPIAware() | Out-Null } catch { }
    [System.Windows.Forms.Application]::EnableVisualStyles()
    $g = [System.Drawing.Graphics]::FromHwnd([IntPtr]::Zero); $k = $g.DpiX / 96.0; $g.Dispose()
    $S = { param($v) [int][Math]::Round($v * $k) }
    $old = $null; try { $old = (Get-ItemProperty -Path $UninstKey -ErrorAction Stop).DisplayVersion } catch { }
    $fg = [System.Drawing.ColorTranslator]::FromHtml('#1b1b1d'); $mu = [System.Drawing.ColorTranslator]::FromHtml('#6b6b70')
    $f = New-Object System.Windows.Forms.Form
    $f.Text = "$AppName 설치"; $f.FormBorderStyle = 'FixedDialog'; $f.MaximizeBox = $false; $f.MinimizeBox = $false
    $f.StartPosition = 'CenterScreen'; $f.ClientSize = New-Object System.Drawing.Size((& $S 480), (& $S 350))
    $f.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#fbfaf7'); $f.Font = New-Object System.Drawing.Font('Malgun Gothic', 9.5)
    $bmp = New-AppBitmap 64; $f.Icon = [System.Drawing.Icon]::FromHandle((New-AppBitmap 32).GetHicon())
    $pic = New-Object System.Windows.Forms.PictureBox; $pic.Image = $bmp; $pic.SizeMode = 'Zoom'
    $pic.Bounds = New-Object System.Drawing.Rectangle((& $S 28), (& $S 28), (& $S 52), (& $S 52)); $f.Controls.Add($pic)
    $t1 = New-Object System.Windows.Forms.Label; $t1.Text = $AppName; $t1.Font = New-Object System.Drawing.Font('Malgun Gothic', 17, [System.Drawing.FontStyle]::Bold)
    $t1.ForeColor = $fg; $t1.AutoSize = $true; $t1.Location = New-Object System.Drawing.Point((& $S 94), (& $S 24)); $f.Controls.Add($t1)
    $t2 = New-Object System.Windows.Forms.Label; $t2.Text = "팀 휴가 + 내 일정 데스크톱 위젯 · 버전 $AppVersion"; $t2.ForeColor = $mu; $t2.AutoSize = $true
    $t2.Location = New-Object System.Drawing.Point((& $S 96), (& $S 62)); $f.Controls.Add($t2)
    $info = New-Object System.Windows.Forms.Label; $info.AutoSize = $false; $info.ForeColor = $fg
    $info.Bounds = New-Object System.Drawing.Rectangle((& $S 28), (& $S 104), (& $S 424), (& $S 24))
    $info.Text = if ($old -and $old -ne $AppVersion) { "설치된 버전 $old → $AppVersion 으로 업데이트해요." } elseif ($old) { "같은 버전($old)을 다시 설치해요. 로그인 정보와 설정은 그대로예요." } else { "이 PC에 $AppName 을 설치해요." }
    $f.Controls.Add($info)
    $cbs = @()
    $y = 136
    foreach ($o in @(@('바탕화면 바로가기 만들기', $true), @('Windows 시작 시 자동으로 실행', -not (Test-Path $NoAutoFlag)), @('설치가 끝나면 바로 실행', $true))) {
        $cb = New-Object System.Windows.Forms.CheckBox; $cb.Text = $o[0]; $cb.Checked = $o[1]; $cb.AutoSize = $true; $cb.ForeColor = $fg
        $cb.Location = New-Object System.Drawing.Point((& $S 30), (& $S $y)); $f.Controls.Add($cb); $cbs += $cb; $y += 30
    }
    $loc = New-Object System.Windows.Forms.Label; $loc.AutoSize = $false; $loc.ForeColor = $mu; $loc.Font = New-Object System.Drawing.Font('Malgun Gothic', 8.5)
    $loc.Bounds = New-Object System.Drawing.Rectangle((& $S 28), (& $S 236), (& $S 424), (& $S 36))
    $loc.Text = "설치 위치: $AppDir`n관리자 권한이 필요 없고, 제어판 > 프로그램 및 기능에서 제거할 수 있어요."; $f.Controls.Add($loc)
    $bar = New-Object System.Windows.Forms.ProgressBar; $bar.Style = 'Marquee'; $bar.Visible = $false
    $bar.Bounds = New-Object System.Drawing.Rectangle((& $S 28), (& $S 282), (& $S 424), (& $S 6)); $f.Controls.Add($bar)
    $ok = New-Object System.Windows.Forms.Button; $ok.Text = '설치'; $ok.Size = New-Object System.Drawing.Size((& $S 104), (& $S 34))
    $ok.Location = New-Object System.Drawing.Point((& $S 236), (& $S 298)); $ok.FlatStyle = 'Flat'; $ok.BackColor = $fg; $ok.ForeColor = [System.Drawing.Color]::White
    $ok.FlatAppearance.BorderSize = 0; $ok.Font = New-Object System.Drawing.Font('Malgun Gothic', 9.5, [System.Drawing.FontStyle]::Bold); $f.Controls.Add($ok)
    $cancel = New-Object System.Windows.Forms.Button; $cancel.Text = '취소'; $cancel.Size = New-Object System.Drawing.Size((& $S 104), (& $S 34))
    $cancel.Location = New-Object System.Drawing.Point((& $S 348), (& $S 298)); $cancel.FlatStyle = 'Flat'; $cancel.BackColor = [System.Drawing.Color]::White
    $cancel.FlatAppearance.BorderColor = [System.Drawing.ColorTranslator]::FromHtml('#d8d4cb'); $f.Controls.Add($cancel)
    $f.AcceptButton = $ok; $f.CancelButton = $cancel
    $script:setupDone = $false
    $cancel.Add_Click({ $f.Close() })
    $ok.Add_Click({
        if ($script:setupDone) { $f.Close(); return }
        $ok.Enabled = $false; $cancel.Enabled = $false; foreach ($c in $cbs) { $c.Enabled = $false }
        $bar.Visible = $true; $info.Text = '설치하는 중이에요…'; $f.Refresh(); [System.Windows.Forms.Application]::DoEvents()
        try {
            Install-App $cbs[0].Checked $cbs[1].Checked
            $bar.Visible = $false
            $script:setupDone = $true
            $info.Text = "설치를 마쳤어요. ($AppVersion)"
            if ($cbs[2].Checked) {
                Start-Process "$env:SystemRoot\System32\wscript.exe" -ArgumentList "`"$Launcher`""
                $info.Text = "설치를 마쳤어요. 위젯을 띄우는 중이에요…"
            }
            $ok.Text = '닫기'; $ok.Enabled = $true
        } catch {
            $bar.Visible = $false; $ok.Enabled = $true; $cancel.Enabled = $true
            $info.Text = "설치하지 못했어요: $($_.Exception.Message)"; Write-Log "setup: $($_.Exception.Message)"
        }
    })
    [void]$f.ShowDialog()
    # 관리자 우회용 임시 폴더 정리
    $pub = Join-Path $env:PUBLIC 'TeamCal_setup'
    if ($PSCommandPath -like "$pub*") { Start-Process "$env:SystemRoot\System32\cmd.exe" -ArgumentList "/c timeout /t 3 /nobreak >nul & rmdir /s /q `"$pub`"" -WindowStyle Hidden }
    # exe 가 임시 폴더에 푼 설치 파일 정리
    $here = Split-Path -Parent $PSCommandPath
    if ((Split-Path -Leaf $here) -like 'TeamCal_setup_*') { Start-Process "$env:SystemRoot\System32\cmd.exe" -ArgumentList "/c timeout /t 3 /nobreak >nul & rmdir /s /q `"$here`"" -WindowStyle Hidden }
}

if ($Uninstall) { Invoke-Uninstall; exit 0 }
if ($Setup -or ($PSCommandPath -and ($PSCommandPath -ne $Installed))) { Show-Setup; exit 0 }

try {
    New-Item -ItemType Directory -Force -Path $AppDir, $LibDir, $DataDir, $UiDir | Out-Null

    # ---- 1) 중복 실행 방지 ----
    $mutex = New-Object System.Threading.Mutex($false, 'Local\TeamLeaveWidget')
    $running = $false
    try { $running = -not $mutex.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { }
    if ($running) {
        if ($PSCommandPath -and ($PSCommandPath -ne $Installed)) {
            [System.Windows.Forms.MessageBox]::Show("위젯이 이미 실행 중이라 새 버전을 설치할 수 없어요.`n`n작업 표시줄 오른쪽 아래 트레이의 TeamCal 아이콘을 오른쪽 클릭 → [위젯 종료] 한 뒤`n'TeamCal 설치.cmd' 를 다시 실행해 주세요.", $AppName, 'OK', 'Information') | Out-Null
        }
        exit 0
    }

    # ---- 2) 설치 상태 유지 (업데이트 후에도 제어판 등록·런처를 최신으로) ----
    try { Write-Launchers } catch { Write-Log "launchers: $($_.Exception.Message)" }
    if (-not (Test-Path $IconFile)) { Save-AppIcon }
    Register-App
    # 예전 이름의 바로가기 정리 → TeamCal 로 통일
    foreach ($on in $OldNames) {
        foreach ($dir in @([Environment]::GetFolderPath('Startup'), [Environment]::GetFolderPath('Desktop'))) {
            $old = Join-Path $dir "$on.lnk"
            if (Test-Path -LiteralPath $old) {
                Remove-Item -LiteralPath $old -Force -ErrorAction SilentlyContinue
                if ($dir -eq [Environment]::GetFolderPath('Desktop') -and (Test-Path $Launcher) -and -not (Test-Path $DesktopLnk)) { try { New-Shortcut $DesktopLnk } catch { } }
            }
        }
    }
    # Windows 시작 시 실행 (설치할 때 끄지 않았다면, 바로가기가 지워졌어도 다시 만든다)
    if ((Test-Path $Launcher) -and -not (Test-Path $NoAutoFlag) -and -not (Test-Path $StartupLnk)) { try { New-Shortcut $StartupLnk } catch { Write-Log "startup: $($_.Exception.Message)" } }
    [IO.File]::WriteAllText((Join-Path $UiDir 'widget.html'), $WidgetHtml, $Utf8)
    [IO.File]::WriteAllText($GuideFile, $GuideText, (New-Object System.Text.UTF8Encoding($true)))

    # ---- 3) WebView2 라이브러리 (최초 1회 다운로드) ----
    $coreDll = Join-Path $LibDir 'Microsoft.Web.WebView2.Core.dll'
    $wfDll   = Join-Path $LibDir 'Microsoft.Web.WebView2.WinForms.dll'
    $loader  = Join-Path $LibDir 'WebView2Loader.dll'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    if (-not ((Test-Path $coreDll) -and (Test-Path $wfDll) -and (Test-Path $loader))) {
        $zip = Join-Path $env:TEMP 'tlw_webview2.zip'
        $ext = Join-Path $env:TEMP 'tlw_webview2'
        try {
            Invoke-WebRequest 'https://www.nuget.org/api/v2/package/Microsoft.Web.WebView2' -OutFile $zip -UseBasicParsing
        } catch { Fail "WebView2 구성요소를 내려받지 못했습니다.`n인터넷 연결(또는 회사 방화벽)을 확인해 주세요.`n`n$($_.Exception.Message)" }
        if (Test-Path $ext) { Remove-Item $ext -Recurse -Force }
        Expand-Archive -LiteralPath $zip -DestinationPath $ext -Force
        $net = Get-ChildItem (Join-Path $ext 'lib') -Directory | Where-Object { $_.Name -like 'net4*' } | Sort-Object Name | Select-Object -First 1
        Copy-Item (Join-Path $net.FullName 'Microsoft.Web.WebView2.Core.dll'), (Join-Path $net.FullName 'Microsoft.Web.WebView2.WinForms.dll') $LibDir -Force
        $arch = switch ($env:PROCESSOR_ARCHITECTURE) { 'ARM64' { 'win-arm64' } 'x86' { 'win-x86' } default { 'win-x64' } }
        Copy-Item (Join-Path $ext "runtimes\$arch\native\WebView2Loader.dll") $LibDir -Force
        Get-ChildItem $LibDir | Unblock-File
        Remove-Item $zip, $ext -Recurse -Force -ErrorAction SilentlyContinue
    }
    $env:PATH = "$LibDir;$env:PATH"
    Add-Type -LiteralPath $coreDll
    Add-Type -LiteralPath $wfDll
    try { [Microsoft.Web.WebView2.Core.CoreWebView2Environment]::SetLoaderDllFolderPath($LibDir) } catch { }

    $rtVer = $null
    try { $rtVer = [Microsoft.Web.WebView2.Core.CoreWebView2Environment]::GetAvailableBrowserVersionString() } catch { }
    if (-not $rtVer) {
        $r = [System.Windows.Forms.MessageBox]::Show("이 PC에 Microsoft Edge WebView2 런타임이 없습니다.`n(위젯 화면을 표시하는 데 필요한 무료 구성요소입니다)`n`n'예'를 누르면 설치 페이지가 열립니다. 설치 후 위젯을 다시 실행해 주세요.", $AppName, 'YesNo', 'Warning')
        if ($r -eq 'Yes') { Start-Process 'https://developer.microsoft.com/microsoft-edge/webview2/#download' }
        exit 1
    }

    Add-Type -ReferencedAssemblies System.Net.Http, System -TypeDefinition @"
using System; using System.Net; using System.Net.Http; using System.Text; using System.Threading.Tasks;
using System.Collections.Generic; using System.Runtime.InteropServices;
public static class TLW {
  [DllImport("user32.dll")] public static extern bool ReleaseCapture();
  [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, int msg, int w, int l);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr h, int attr, ref int val, int size);
  [DllImport("shell32.dll", CharSet = CharSet.Unicode)] public static extern int SetCurrentProcessExplicitAppUserModelID(string id);
  public static readonly HttpClient Http = new HttpClient() { Timeout = TimeSpan.FromSeconds(30) };
  public static async Task<string> PostForm(string url, Dictionary<string,string> f) {
    var r = await Http.PostAsync(url, new FormUrlEncodedContent(f)).ConfigureAwait(false);
    var b = await r.Content.ReadAsByteArrayAsync().ConfigureAwait(false);
    return ((int)r.StatusCode).ToString() + "\n" + Encoding.UTF8.GetString(b);
  }
  public static async Task<string> GetText(string url) {
    var r = await Http.GetAsync(url).ConfigureAwait(false);
    var b = await r.Content.ReadAsByteArrayAsync().ConfigureAwait(false);
    return ((int)r.StatusCode).ToString() + "\n" + Encoding.UTF8.GetString(b);
  }
  public static async Task<byte[]> GetBytes(string url) {
    var r = await Http.GetAsync(url).ConfigureAwait(false);
    r.EnsureSuccessStatusCode();
    return await r.Content.ReadAsByteArrayAsync().ConfigureAwait(false);
  }
  public static System.Net.Sockets.TcpListener Listen() {
    var l = new System.Net.Sockets.TcpListener(IPAddress.Loopback, 0); l.Start(); return l;
  }
  public static int PortOf(System.Net.Sockets.TcpListener l) { return ((IPEndPoint)l.LocalEndpoint).Port; }
  // 브라우저가 http://127.0.0.1:포트/?code=... 로 돌아오면 code 를 돌려준다 (관리자 권한 필요 없음)
  public static async Task<string> WaitCode(System.Net.Sockets.TcpListener l, string html) {
    try {
      while (true) {
        using (var c = await l.AcceptTcpClientAsync().ConfigureAwait(false)) {
          var st = c.GetStream();
          var buf = new byte[16384];
          int n = await st.ReadAsync(buf, 0, buf.Length).ConfigureAwait(false);
          string req = Encoding.ASCII.GetString(buf, 0, Math.Max(n, 0));
          string first = req.Split('\n')[0];
          string[] parts = first.Split(' ');
          string path = parts.Length > 1 ? parts[1] : "";
          int qi = path.IndexOf('?');
          string q = qi >= 0 ? path.Substring(qi) : "";
          bool done = q.Contains("code=") || q.Contains("error=");
          byte[] body = Encoding.UTF8.GetBytes(done ? html : "");
          byte[] head = Encoding.ASCII.GetBytes("HTTP/1.1 " + (done ? "200 OK" : "404 Not Found") + "\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: " + body.Length + "\r\nConnection: close\r\n\r\n");
          await st.WriteAsync(head, 0, head.Length).ConfigureAwait(false);
          await st.WriteAsync(body, 0, body.Length).ConfigureAwait(false);
          await st.FlushAsync().ConfigureAwait(false);
          if (done) return q;
        }
      }
    } finally { try { l.Stop(); } catch { } }
  }
}
"@
    [TLW]::SetProcessDPIAware() | Out-Null
    # 작업 표시줄에 PowerShell 아이콘 대신 TeamCal 아이콘이 보이도록 (별도 앱으로 묶기)
    try { [TLW]::SetCurrentProcessExplicitAppUserModelID('TeamCal.Widget') | Out-Null } catch { Write-Log "aumid: $($_.Exception.Message)" }
    [System.Windows.Forms.Application]::EnableVisualStyles()

    # ---- 4) 저장된 설정 ----
    $g = [System.Drawing.Graphics]::FromHwnd([IntPtr]::Zero); $scale = $g.DpiX / 96.0; $g.Dispose()
    $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $script:state = @{
        X = -1; Y = -1; Top = $false; Opacity = 1.0; HoverOpaque = $true
        Theme = 'light'; Size = 1.0; GMode = ''; ICal = ''; AutoLogin = $true
        W = 0; H = 0      # 사용자가 정한 크기(DIP). 0 이면 기본 너비 / 내용에 맞춘 높이
    }
    if (Test-Path $StateFile) {
        try { (Get-Content $StateFile -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $script:state[$_.Name] = $_.Value } } catch { }
    }
    function Get-W {
        $w = if ([double]$script:state.W -gt 0) { [double]$script:state.W } else { 360 * [double]$script:state.Size }
        [int][Math]::Round($w * $scale)
    }
    function Get-H { if ([double]$script:state.H -gt 0) { [int][Math]::Round([double]$script:state.H * $scale) } else { [int](640 * $scale) } }
    $onScreen = $false
    foreach ($scr in [System.Windows.Forms.Screen]::AllScreens) {
        if ($scr.WorkingArea.Contains([int]$state.X + 40, [int]$state.Y + 10)) { $onScreen = $true }
    }
    if (-not $onScreen) { $state.X = $wa.Right - (Get-W) - [int](20 * $scale); $state.Y = $wa.Top + [int](20 * $scale) }

    # ---- 5) 아이콘 (점 달력 모양) ----
    $bmp = New-AppBitmap ([int][Math]::Max(32, [Math]::Round(48 * $scale)))     # 작업 표시줄용 (크게 그려서 선명하게)
    $icon = [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
    $trayIcon = [System.Drawing.Icon]::FromHandle((New-AppBitmap ([int][Math]::Max(16, [Math]::Round(16 * $scale)))).GetHicon())

    # ---- 6) 창 ----
    $form = New-Object System.Windows.Forms.Form
    $form.Text = $AppName
    $form.Icon = $icon
    $form.FormBorderStyle = 'None'
    $form.ShowInTaskbar = $true       # — 를 누르면 작업 표시줄로 내려감
    $form.MaximizeBox = $false        # 머리글 더블클릭으로 최대화되지 않게
    $form.MinimizeBox = $true         # 작업 표시줄 버튼으로 내리기/올리기
    $form.StartPosition = 'Manual'
    $form.Bounds = New-Object System.Drawing.Rectangle([int]$state.X, [int]$state.Y, (Get-W), (Get-H))
    $form.MinimumSize = New-Object System.Drawing.Size([int](280 * $scale), [int](220 * $scale))
    $form.TopMost = [bool]$state.Top
    $form.BackColor = if ($state.Theme -eq 'dark') { [System.Drawing.ColorTranslator]::FromHtml('#111113') } else { [System.Drawing.ColorTranslator]::FromHtml('#fbfaf7') }

    $wv = New-Object Microsoft.Web.WebView2.WinForms.WebView2
    $wv.Dock = 'Fill'
    $wv.DefaultBackgroundColor = $form.BackColor
    $form.Controls.Add($wv)

    # ---- 7) 공통 함수 ----
    function Save-State {
        if ($script:uninstalling) { return }
        if ($form.WindowState -ne 'Normal') { return }
        $script:state.X = $form.Left; $script:state.Y = $form.Top
        $script:state.Top = $form.TopMost
        try { [IO.File]::WriteAllText($StateFile, ($script:state | ConvertTo-Json), $Utf8) } catch { }
    }
    function Send-To($w, $obj) {
        try { if ($w -and $w.CoreWebView2) { $w.CoreWebView2.PostWebMessageAsJson(($obj | ConvertTo-Json -Compress -Depth 8)) } } catch { Write-Log "Send: $($_.Exception.Message)" }
    }
    function Send-Main($obj) { Send-To $wv $obj }
    function Send-Pop($obj)  { if ($script:pop) { Send-To $script:pop.W $obj } }
    function Send-UI($obj)   { Send-Main $obj; Send-Pop $obj }      # 위젯 + 떠 있는 팝업 창 모두에게
    # 위젯 최대 높이 (사용자가 높이를 정했으면 그 높이, 아니면 화면 높이) — 내용이 적으면 그만큼 줄어든다
    function Get-MaxH {
        $scr = [System.Windows.Forms.Screen]::FromControl($form).WorkingArea.Height - [int](20 * $scale)
        if ([double]$script:state.H -gt 0) { return [int][Math]::Min($scr, [Math]::Round([double]$script:state.H * $scale)) }
        return [int]$scr
    }
    function Send-Config {
        Send-UI @{ type = 'config'; theme = [string]$script:state.Theme; pinned = [bool]$form.TopMost; gmode = [string]$script:state.GMode; fixed = ([double]$script:state.H -gt 0); autoLogin = [bool]$script:state.AutoLogin; version = $AppVersion; maxH = (Get-MaxH) }
    }

    # 비동기 작업: .NET Task 를 UI 타이머로 확인 (PowerShell 스크립트는 항상 UI 스레드에서 실행)
    $script:jobs = New-Object System.Collections.ArrayList
    function Add-Job($task, [scriptblock]$done, $ctx) { [void]$script:jobs.Add(@{ T = $task; D = $done; C = $ctx }) }
    $jobTimer = New-Object System.Windows.Forms.Timer
    $jobTimer.Interval = 150
    $jobTimer.Add_Tick({
        for ($i = $script:jobs.Count - 1; $i -ge 0; $i--) {
            $j = $script:jobs[$i]
            if (-not $j.T.IsCompleted) { continue }
            $script:jobs.RemoveAt($i)
            try { & $j.D $j.T $j.C } catch { Write-Log "job: $($_.Exception.Message)" }
        }
    })
    function Split-Resp([string]$s) { $i = $s.IndexOf("`n"); @{ Code = [int]$s.Substring(0, $i); Body = $s.Substring($i + 1) } }
    function Task-Error($t) { if ($t.Exception) { $t.Exception.GetBaseException().Message } else { '시간 초과' } }

    # 투명도
    function Apply-Opacity {
        $o = [double]$script:state.Opacity
        $target = $o
        if ($o -lt 1 -and $script:state.HoverOpaque -and $form.Visible -and $form.Bounds.Contains([System.Windows.Forms.Cursor]::Position)) { $target = 0.999 }
        if ([Math]::Abs($form.Opacity - $target) -gt 0.0005) { $form.Opacity = $target }
    }
    $OpaSteps = @(1.0, 0.9, 0.8, 0.7, 0.6, 0.5)
    function Set-Opacity($v) { $script:state.Opacity = [double]$v; Apply-Opacity; Save-State }
    function Next-Opacity {
        $cur = [double]$script:state.Opacity; $idx = 0
        for ($i = 0; $i -lt $OpaSteps.Count; $i++) { if ([Math]::Abs($OpaSteps[$i] - $cur) -lt 0.01) { $idx = $i } }
        Set-Opacity $OpaSteps[($idx + 1) % $OpaSteps.Count]
    }
    function Set-Theme($t) {
        $script:state.Theme = $t
        $form.BackColor = if ($t -eq 'dark') { [System.Drawing.ColorTranslator]::FromHtml('#111113') } else { [System.Drawing.ColorTranslator]::FromHtml('#fbfaf7') }
        try { $wv.DefaultBackgroundColor = $form.BackColor } catch { }
        Send-UI @{ type = 'theme'; theme = $t }; Save-State
    }
    function Toggle-Pin { $form.TopMost = -not $form.TopMost; Send-UI @{ type = 'pinned'; on = [bool]$form.TopMost }; Save-State }
    function Set-Size($v) {
        $script:state.Size = [double]$v
        try { $wv.ZoomFactor = [double]$v } catch { }
        if ([double]$script:state.W -le 0) { $form.Width = Get-W }
        Save-State
    }
    function Reset-Size {
        $script:state.W = 0; $script:state.H = 0
        $form.Width = Get-W
        Send-UI @{ type = 'fixed'; on = $false; maxH = (Get-MaxH) }; Save-State
    }

    # ---------------- 구글 로그인 (OAuth, 브라우저 + 로컬 리디렉션) ----------------
    function Get-GClient {
        if (-not (Test-Path $GClientFile)) { return $null }
        try {
            $j = Get-Content $GClientFile -Raw -Encoding UTF8 | ConvertFrom-Json
            $c = if ($j.installed) { $j.installed } elseif ($j.web) { $j.web } else { $j }
            if (-not $c.client_id) { return $null }
            return @{ Id = [string]$c.client_id; Secret = [string]$c.client_secret }
        } catch { return $null }
    }
    # 설정 파일이 없으면 TeamCal 사이트에서 자동으로 받아 온다 (올려 둔 경우에만)
    $GClientUrl = ($UpdateUrl -replace 'version\.json$', 'google_client.json')
    function Save-GClientText([string]$txt) {
        try {
            $j = $txt | ConvertFrom-Json
            if (-not $j.installed -or -not $j.installed.client_id) { return $false }
            [IO.File]::WriteAllText($GClientFile, $txt, (New-Object Text.UTF8Encoding $false))
            return $true
        } catch { return $false }
    }
    function Fetch-GClientNow {
        try {
            $t = [TLW]::GetText($GClientUrl + '?t=' + [DateTime]::UtcNow.Ticks)
            if (-not $t.Wait(7000)) { return $false }
            $r = $t.Result; $i = $r.IndexOf("`n")
            if ($r.Substring(0, $i) -ne '200') { return $false }
            return (Save-GClientText $r.Substring($i + 1))
        } catch { return $false }
    }
    function Fetch-GClientBg {
        if (Test-Path $GClientFile) { return }
        Add-Job ([TLW]::GetText($GClientUrl + '?t=' + [DateTime]::UtcNow.Ticks)) {
            param($t, $ctx)
            if ($t.IsFaulted -or $t.IsCanceled) { return }
            $r = $t.Result; $i = $r.IndexOf("`n")
            if ($r.Substring(0, $i) -eq '200') { [void](Save-GClientText $r.Substring($i + 1)) }
        }
    }
    function Import-GClient {
        $dlg = New-Object System.Windows.Forms.OpenFileDialog
        $dlg.Title = '구글 클라우드에서 받은 OAuth 클라이언트 JSON 파일 선택'
        $dlg.Filter = 'JSON 파일 (*.json)|*.json'
        $dlg.InitialDirectory = Join-Path $env:USERPROFILE 'Downloads'
        $was = $form.TopMost; $form.TopMost = $false
        $ok = $dlg.ShowDialog($form) -eq 'OK'
        $form.TopMost = $was
        if (-not $ok) { return $false }
        try {
            $j = Get-Content $dlg.FileName -Raw -Encoding UTF8 | ConvertFrom-Json
            $c = if ($j.installed) { $j.installed } elseif ($j.web) { $j.web } else { $j }
            if (-not $c.client_id -or -not $c.client_secret) { throw 'client_id 없음' }
            if ($j.web) {
                [System.Windows.Forms.MessageBox]::Show("'웹 애플리케이션' 유형의 파일이에요.`n구글 클라우드에서 클라이언트를 만들 때 유형을 '데스크톱 앱'으로 골라 주세요.", $AppName, 'OK', 'Warning') | Out-Null
                return $false
            }
            Copy-Item $dlg.FileName $GClientFile -Force
            Remove-Item $GTokenFile -ErrorAction SilentlyContinue
            return $true
        } catch {
            [System.Windows.Forms.MessageBox]::Show("올바른 구글 OAuth 클라이언트 파일이 아니에요.`n'구글 캘린더 연결 방법' 안내의 5단계에서 받은 JSON 파일을 골라 주세요.", $AppName, 'OK', 'Warning') | Out-Null
            return $false
        }
    }
    $script:gRT = $null      # 자동 로그인을 끈 경우 로그인 정보는 메모리에만 둔다
    function Save-RefreshToken([string]$rt) {
        $script:gRT = $rt
        if (-not [bool]$script:state.AutoLogin) { Remove-Item $GTokenFile -ErrorAction SilentlyContinue; return }
        $sec = ConvertTo-SecureString $rt -AsPlainText -Force
        Set-Content -LiteralPath $GTokenFile -Value (ConvertFrom-SecureString $sec) -Encoding ASCII   # Windows 계정으로 암호화(DPAPI)
    }
    function Read-RefreshToken {
        if ($script:gRT) { return $script:gRT }
        if (-not (Test-Path $GTokenFile)) { return $null }
        try {
            $sec = ConvertTo-SecureString (Get-Content $GTokenFile -Raw).Trim()
            $b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
            try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b) }
        } catch { return $null }
    }
    function B64Url([byte[]]$b) { [Convert]::ToBase64String($b).TrimEnd('=').Replace('+', '-').Replace('/', '_') }
    function New-Random([int]$n) { $b = New-Object byte[] $n; [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b); B64Url $b }
    function New-Dict([hashtable]$h) { $d = New-Object 'System.Collections.Generic.Dictionary[string,string]'; foreach ($k in $h.Keys) { $d[$k] = [string]$h[$k] }; return $d }
    function Parse-Query([string]$q) {
        $r = @{}; foreach ($p in $q.TrimStart('?').Split('&')) { $kv = $p.Split('=', 2); if ($kv.Count -eq 2) { $r[[Uri]::UnescapeDataString($kv[0])] = [Uri]::UnescapeDataString($kv[1].Replace('+', ' ')) } }; return $r
    }
    $script:gAT = $null; $script:gExp = [DateTime]::MinValue; $script:gBusy = $false; $script:gListener = $null

    function Start-GoogleLogin {
        $c = Get-GClient
        if (-not $c -and (Fetch-GClientNow)) { $c = Get-GClient }
        if (-not $c) {
            $r = [System.Windows.Forms.MessageBox]::Show("구글 로그인을 쓰려면 처음 한 번 구글 클라우드 설정 파일(JSON)이 필요해요.`n`n예: 설정 파일 불러오기`n아니요: 설정 방법 보기", $AppName, 'YesNoCancel', 'Information')
            if ($r -eq 'No') { Start-Process notepad.exe -ArgumentList "`"$GuideFile`""; Set-GMode 'google'; return }
            if ($r -ne 'Yes') { return }
            if (-not (Import-GClient)) { return }
            $c = Get-GClient
        }
        $script:state.GMode = 'google'; Save-State
        if ($script:gListener) { try { $script:gListener.Stop() } catch { } }
        try { $l = [TLW]::Listen() } catch { [System.Windows.Forms.MessageBox]::Show("로그인 준비 중 오류가 났어요.`n$($_.Exception.Message)", $AppName) | Out-Null; return }
        $script:gListener = $l
        $redirect = "http://127.0.0.1:$([TLW]::PortOf($l))/"
        $verifier  = New-Random 48
        $sha       = [Security.Cryptography.SHA256]::Create()
        $challenge = B64Url ($sha.ComputeHash([Text.Encoding]::ASCII.GetBytes($verifier)))
        $st        = New-Random 16
        $ctx = @{ Verifier = $verifier; Redirect = $redirect; State = $st; Client = $c }
        Add-Job ([TLW]::WaitCode($l, $LoginDoneHtml)) {
            param($t, $ctx)
            $script:gListener = $null
            if ($t.IsFaulted -or $t.IsCanceled) { return }
            $q = Parse-Query $t.Result
            if ($q.error -or $q.state -ne $ctx.State -or -not $q.code) {
                Send-UI @{ type = 'gtoken'; error = '구글 로그인이 취소되었거나 실패했어요.' }; return
            }
            $body = New-Dict @{ code = $q.code; client_id = $ctx.Client.Id; client_secret = $ctx.Client.Secret; redirect_uri = $ctx.Redirect; grant_type = 'authorization_code'; code_verifier = $ctx.Verifier }
            Add-Job ([TLW]::PostForm('https://oauth2.googleapis.com/token', $body)) {
                param($t2, $c2)
                if ($t2.IsFaulted -or $t2.IsCanceled) { Send-UI @{ type = 'gtoken'; error = "구글에 연결하지 못했어요. ($(Task-Error $t2))" }; return }
                $r = Split-Resp $t2.Result
                $j = $r.Body | ConvertFrom-Json
                if ($r.Code -ne 200 -or -not $j.access_token) { Write-Log "token exchange $($r.Code): $($r.Body)"; Send-UI @{ type = 'gtoken'; error = '구글 로그인 확인에 실패했어요. 다시 시도해 주세요.' }; return }
                if ($j.refresh_token) { Save-RefreshToken $j.refresh_token }
                $script:gAT = $j.access_token; $script:gExp = (Get-Date).AddSeconds([int]$j.expires_in - 60)
                Send-UI @{ type = 'gtoken'; token = $script:gAT }
                try { $form.Activate() } catch { }
            } $null
        } $ctx
        $scope = [Uri]::EscapeDataString('https://www.googleapis.com/auth/calendar.readonly https://www.googleapis.com/auth/calendar.events https://www.googleapis.com/auth/calendar.app.created')
        $url = "https://accounts.google.com/o/oauth2/v2/auth?client_id=$([Uri]::EscapeDataString($c.Id))&redirect_uri=$([Uri]::EscapeDataString($redirect))&response_type=code&scope=$scope&code_challenge=$challenge&code_challenge_method=S256&access_type=offline&prompt=consent&state=$st"
        Send-UI @{ type = 'gmode'; gmode = 'google' }
        Send-UI @{ type = 'gstatus'; status = 'waiting' }
        Start-Process $url
    }
    function Request-GToken([bool]$force) {
        if (-not $force -and $script:gAT -and (Get-Date) -lt $script:gExp) { Send-UI @{ type = 'gtoken'; token = $script:gAT }; return }
        $c = Get-GClient
        if (-not $c) { Send-UI @{ type = 'gtoken'; need = 'client' }; return }
        $rt = Read-RefreshToken
        if (-not $rt) { Send-UI @{ type = 'gtoken'; need = 'login' }; return }
        if ($script:gBusy) { return }
        $script:gBusy = $true
        $body = New-Dict @{ client_id = $c.Id; client_secret = $c.Secret; refresh_token = $rt; grant_type = 'refresh_token' }
        Add-Job ([TLW]::PostForm('https://oauth2.googleapis.com/token', $body)) {
            param($t, $x)
            $script:gBusy = $false
            if ($t.IsFaulted -or $t.IsCanceled) { Send-UI @{ type = 'gtoken'; error = "구글에 연결하지 못했어요. 인터넷 연결을 확인해 주세요." }; return }
            $r = Split-Resp $t.Result
            $j = $null; try { $j = $r.Body | ConvertFrom-Json } catch { }
            if ($r.Code -eq 200 -and $j.access_token) {
                $script:gAT = $j.access_token; $script:gExp = (Get-Date).AddSeconds([int]$j.expires_in - 60)
                Send-UI @{ type = 'gtoken'; token = $script:gAT }
            } elseif ($j -and $j.error -eq 'invalid_grant') {
                Remove-Item $GTokenFile -ErrorAction SilentlyContinue; $script:gAT = $null; $script:gRT = $null
                Send-UI @{ type = 'gtoken'; need = 'login' }
            } else {
                Write-Log "token refresh $($r.Code): $($r.Body)"
                Send-UI @{ type = 'gtoken'; error = '구글 일정을 불러오지 못했어요.' }
            }
        } $null
    }
    function Disconnect-Google {
        $rt = Read-RefreshToken
        if ($rt) { try { [void][TLW]::PostForm('https://oauth2.googleapis.com/revoke', (New-Dict @{ token = $rt })) } catch { } }   # 구글 쪽 로그인도 해제
        Remove-Item $GTokenFile -ErrorAction SilentlyContinue
        $script:gRT = $null
        $script:gAT = $null
        Set-GMode ''
    }
    function Set-GMode($m) { $script:state.GMode = $m; Save-State; Send-UI @{ type = 'gmode'; gmode = $m } }

    # iCal
    function Set-ICal {
        $was = $form.TopMost; $form.TopMost = $false
        $prompt = "구글 캘린더(웹) → ⚙ 설정 → 왼쪽 '내 캘린더의 설정'에서 캘린더 선택 →`n'캘린더 통합' → 'iCal 형식의 비공개 주소'를 복사해 붙여넣으세요.`n`n(이 주소는 비밀번호처럼 다른 사람에게 공유하지 마세요)"
        $v = [Microsoft.VisualBasic.Interaction]::InputBox($prompt, "$AppName - iCal 주소로 연결", [string]$script:state.ICal)
        $form.TopMost = $was
        $v = $v.Trim()
        if (-not $v) { return }
        if ($v -match '^webcal://') { $v = 'https://' + $v.Substring(9) }
        if ($v -notmatch '^https://') { [System.Windows.Forms.MessageBox]::Show('주소는 https:// 로 시작해야 해요.', $AppName, 'OK', 'Warning') | Out-Null; return }
        $script:state.ICal = $v
        Set-GMode 'ical'
    }
    $script:icsBusy = $false
    function Request-ICS {
        if (-not $script:state.ICal) { Send-UI @{ type = 'ics'; error = 'iCal 주소가 없어요. 메뉴에서 다시 연결해 주세요.' }; return }
        if ($script:icsBusy) { return }
        $script:icsBusy = $true
        Add-Job ([TLW]::GetText([string]$script:state.ICal)) {
            param($t, $x)
            $script:icsBusy = $false
            if ($t.IsFaulted -or $t.IsCanceled) { Send-UI @{ type = 'ics'; error = "iCal 주소에 연결하지 못했어요. ($(Task-Error $t))" }; return }
            $r = Split-Resp $t.Result
            if ($r.Code -ne 200 -or $r.Body -notmatch 'BEGIN:VCALENDAR') { Send-UI @{ type = 'ics'; error = "iCal 주소에서 일정을 받지 못했어요. (응답 $($r.Code))" }; return }
            Send-UI @{ type = 'ics'; text = $r.Body }
        } $null
    }

    # ---------------- 프로그램 제거 ----------------
    function Uninstall-App {
        # 제어판에서 제거할 때와 같은 과정 (확인 창 → 정리)
        if (-not (Test-Path $UninstVbs)) { Write-Launchers }
        Start-Process "$env:SystemRoot\System32\wscript.exe" -ArgumentList "`"$UninstVbs`""
    }

    # ---------------- 자동 업데이트 ----------------
    $script:upd = $null
    function Compare-Ver($a, $b) { try { return ([version]$a).CompareTo([version]$b) } catch { return 0 } }
    $script:lastUpdCheck = [DateTime]::MinValue
    function Check-Update([bool]$manual) {
        $script:lastUpdCheck = [DateTime]::UtcNow
        Add-Job ([TLW]::GetText($UpdateUrl + '?t=' + [DateTime]::UtcNow.Ticks)) {
            param($t, $x)
            if ($t.IsFaulted -or $t.IsCanceled) { if ($x.Manual) { [System.Windows.Forms.MessageBox]::Show("업데이트 정보를 가져오지 못했어요.`n인터넷 연결을 확인해 주세요.", $AppName) | Out-Null }; return }
            $r = Split-Resp $t.Result
            $j = $null; try { $j = $r.Body | ConvertFrom-Json } catch { }
            if ($r.Code -ne 200 -or -not $j -or -not $j.version) { if ($x.Manual) { [System.Windows.Forms.MessageBox]::Show("업데이트 정보가 없어요. (응답 $($r.Code))", $AppName) | Out-Null }; return }
            if ((Compare-Ver ([string]$j.version) $AppVersion) -gt 0) {
                $file = if ($j.url) { [string]$j.url } else { 'TeamLeaveWidget.ps1' }
                $url = ([Uri]::new([Uri]$UpdateUrl, $file)).AbsoluteUri
                $script:upd = @{ Version = [string]$j.version; Url = $url; Notes = [string]$j.notes }
                Send-Main @{ type = 'update'; version = [string]$j.version; notes = [string]$j.notes }
                if ($x.Manual) {
                    $q = [System.Windows.Forms.MessageBox]::Show("새 버전 $($j.version) 이 있어요. (지금 $AppVersion)`n$($j.notes)`n`n지금 업데이트할까요?", $AppName, 'YesNo', 'Question')
                    if ($q -eq 'Yes') { Do-Update }
                }
            } elseif ($x.Manual) {
                [System.Windows.Forms.MessageBox]::Show("최신 버전이에요. ($AppVersion)", $AppName) | Out-Null
            }
        } @{ Manual = $manual }
    }
    function Do-Update {
        $u = $script:upd
        if (-not $u) { return }
        Send-Main @{ type = 'updating' }
        Add-Job ([TLW]::GetBytes($u.Url + '?t=' + [DateTime]::UtcNow.Ticks)) {
            param($t, $u)
            if ($t.IsFaulted -or $t.IsCanceled) { Send-Main @{ type = 'update'; version = $u.Version; error = '새 버전을 받지 못했어요. 다시 눌러 주세요.' }; return }
            $bytes = $t.Result
            $text = [Text.Encoding]::UTF8.GetString($bytes)
            if ($text -notmatch 'TeamLeaveWidget-Package') { Write-Log "update: marker missing"; Send-Main @{ type = 'update'; version = $u.Version; error = '받은 파일이 올바르지 않아요.' }; return }
            try {
                $tmp = "$Installed.new"
                [IO.File]::WriteAllBytes($tmp, $bytes)
                Copy-Item -LiteralPath $Installed -Destination "$Installed.bak" -Force -ErrorAction SilentlyContinue
                Move-Item -LiteralPath $tmp -Destination $Installed -Force
            } catch { Write-Log "update write: $($_.Exception.Message)"; Send-Main @{ type = 'update'; version = $u.Version; error = '업데이트 파일을 바꾸지 못했어요.' }; return }
            Restart-Widget
        } $u
    }
    function Restart-Widget {
        # 지금 위젯이 완전히 꺼진 뒤 다시 켜지도록 잠시 기다렸다 실행
        $rv = Join-Path $AppDir 'restart.vbs'
        @'
WScript.Sleep 2500
Set sh = CreateObject("WScript.Shell")
sh.Run "wscript.exe """ & sh.ExpandEnvironmentStrings("%LOCALAPPDATA%") & "\TeamLeaveWidget\launch.vbs""", 0, False
'@ | Set-Content -LiteralPath $rv -Encoding ASCII
        Start-Process "$env:SystemRoot\System32\wscript.exe" -ArgumentList "`"$rv`""
        $script:reallyExit = $true
        Close-Popup; Save-State; $tray.Visible = $false
        $form.Close()
    }
    $updTimer = New-Object System.Windows.Forms.Timer
    $updTimer.Interval = 30 * 60 * 1000          # 30분마다 새 버전 확인
    $updTimer.Add_Tick({ Check-Update $false })
    # 위젯을 클릭하거나 다시 띄울 때도 (10분에 한 번까지) 확인
    $form.Add_Activated({ if ($script:updChecked -and -not $script:upd -and ([DateTime]::UtcNow - $script:lastUpdCheck).TotalMinutes -ge 10) { Check-Update $false } })

    # ---------------- 떠 있는 팝업 창 (휴가 등록 / 일정 추가) ----------------
    $script:pop = $null
    $script:wvEnv = $null
    function Save-PopPos($p) {
        if (-not $p -or -not $p.F -or $p.F.IsDisposed) { return }
        $script:state["Pop_$($p.Kind)"] = @{ X = $p.F.Left; Y = $p.F.Top }
        Save-State
    }
    function Close-Popup {
        $p = $script:pop
        if (-not $p) { return }
        Save-PopPos $p
        $script:pop = $null
        try { $p.F.Close() } catch { }
        try { $p.F.Dispose() } catch { }
    }
    function Open-Popup([string]$kind, $data) {
        if (@('leave', 'gevent', 'team', 'settings') -notcontains $kind) { return }
        if (-not $script:wvEnv) { return }
        Close-Popup
        $f = New-Object System.Windows.Forms.Form
        $f.FormBorderStyle = 'None'; $f.ShowInTaskbar = $false; $f.StartPosition = 'Manual'
        $f.TopMost = $true; $f.MaximizeBox = $false; $f.MinimizeBox = $false
        $f.Icon = $icon
        $f.Text = switch ($kind) { 'leave' { '휴가 등록' } 'team' { '내 팀원' } 'settings' { 'TeamCal 설정' } default { '일정 추가' } }
        $f.BackColor = $form.BackColor
        $w = [int][Math]::Round(360 * $scale * [double]$script:state.Size)
        $h = [int](520 * $scale)
        # 마지막 위치 (화면 밖이면 위젯 옆)
        $x = $null; $y = $null
        $pos = $script:state["Pop_$kind"]
        if ($pos -and $pos.X -ne $null) {
            $px = [int]$pos.X; $py = [int]$pos.Y
            foreach ($scr in [System.Windows.Forms.Screen]::AllScreens) { if ($scr.WorkingArea.Contains($px + 40, $py + 10)) { $x = $px; $y = $py } }
        }
        if ($x -eq $null) {
            $wa2 = [System.Windows.Forms.Screen]::FromControl($form).WorkingArea
            $gap = [int](12 * $scale)
            $x = $form.Left - $w - $gap
            if ($x -lt $wa2.Left) { $x = [Math]::Min($form.Right + $gap, $wa2.Right - $w) }
            $y = [Math]::Max($wa2.Top, [Math]::Min($form.Top, $wa2.Bottom - $h))
        }
        $f.Bounds = New-Object System.Drawing.Rectangle($x, $y, $w, $h)
        $f.MinimumSize = New-Object System.Drawing.Size([int](260 * $scale), [int](160 * $scale))
        $w2 = New-Object Microsoft.Web.WebView2.WinForms.WebView2
        $w2.Dock = 'Fill'
        $w2.DefaultBackgroundColor = $form.BackColor
        $f.Controls.Add($w2)
        $script:pop = @{ F = $f; W = $w2; Kind = $kind; Data = $data }
        $w2.Add_CoreWebView2InitializationCompleted({
            param($s, $e)
            $p = $script:pop
            if (-not $p) { return }
            if (-not $e.IsSuccess) { Write-Log "popup init: $($e.InitializationException.Message)"; Close-Popup; return }
            $cw = $p.W.CoreWebView2
            $cw.Settings.IsStatusBarEnabled = $false
            $cw.Settings.AreDefaultContextMenusEnabled = $false
            $cw.Settings.IsZoomControlEnabled = $false
            try { $cw.Settings.IsNonClientRegionSupportEnabled = $true } catch { }
            $cw.SetVirtualHostNameToFolderMapping('tlw.app', $UiDir, [Microsoft.Web.WebView2.Core.CoreWebView2HostResourceAccessKind]::Allow)
            $cw.add_NewWindowRequested({ param($s2, $e2) $e2.Handled = $true; if ($e2.Uri -match '^https://') { Start-Process $e2.Uri } })
            $cw.add_WebMessageReceived({
                param($s2, $e2)
                try { On-PopMessage ($e2.WebMessageAsJson | ConvertFrom-Json) } catch { Write-Log "popmsg: $($_.Exception.Message)" }
            })
            $p.W.ZoomFactor = [double]$script:state.Size
            $cw.Navigate("https://tlw.app/widget.html?popup=$($p.Kind)")
        })
        $f.Add_Shown({
            try { $v = 2; [TLW]::DwmSetWindowAttribute($this.Handle, 33, [ref]$v, 4) | Out-Null } catch { }
            if ($script:pop) { $script:pop.W.EnsureCoreWebView2Async($script:wvEnv) | Out-Null }
        })
        $f.Add_FormClosing({ if ($script:pop -and $script:pop.F -eq $this) { Save-PopPos $script:pop; $script:pop = $null } })
        $f.Show()
        $f.Activate()
    }
    # ---- 설정 창 ----
    function Get-Settings {
        @{ theme = [string]$script:state.Theme; opacity = [double]$script:state.Opacity; hover = [bool]$script:state.HoverOpaque
           top = [bool]$form.TopMost; size = [double]$script:state.Size; autostart = (-not (Test-Path $NoAutoFlag))
           autoLogin = [bool]$script:state.AutoLogin; gmode = [string]$script:state.GMode; version = $AppVersion }
    }
    function Reset-Pos {
        Reset-Size
        $form.Left = $wa.Right - $form.Width - [int](20 * $scale); $form.Top = $wa.Top + [int](20 * $scale)
        $form.Show(); Save-State
    }
    function Set-AutoStart([bool]$on) {
        try {
            if ($on) { Remove-Item -LiteralPath $NoAutoFlag -Force -ErrorAction SilentlyContinue; New-Shortcut $StartupLnk }
            else { Set-Content -LiteralPath $NoAutoFlag 'off'; Remove-Item -LiteralPath $StartupLnk -Force -ErrorAction SilentlyContinue }
        } catch { Write-Log "autostart: $($_.Exception.Message)" }
    }
    function Set-AutoLogin([bool]$on) {
        $script:state.AutoLogin = $on; Save-State
        if (-not $on) { Remove-Item $GTokenFile -ErrorAction SilentlyContinue }
        elseif ($script:gRT) { Save-RefreshToken $script:gRT }
    }
    function Apply-Setting([string]$key, $v) {
        switch ($key) {
            'theme'     { Set-Theme ([string]$v) }
            'opacity'   { $o = [double]$v; if ($o -ge 0.3 -and $o -le 1) { Set-Opacity $o } }
            'hover'     { $script:state.HoverOpaque = [bool]$v; Apply-Opacity; Save-State }
            'top'       { if ([bool]$v -ne [bool]$form.TopMost) { Toggle-Pin } }
            'size'      { $z = [double]$v; if ($z -ge 0.8 -and $z -le 1.3) { Set-Size $z; if ($script:pop) { try { $script:pop.W.ZoomFactor = $z } catch { } } } }
            'autostart' { Set-AutoStart ([bool]$v) }
            'autoLogin' { Set-AutoLogin ([bool]$v); Send-Config }
            'ui'        { Send-Main @{ type = 'uipref'; key = [string]$v.key; value = [bool]$v.value } }
            'act'       {
                switch ([string]$v) {
                    'glogin'     { Close-Popup; Start-GoogleLogin }
                    'glogout'    { Disconnect-Google }
                    'gical'      { Close-Popup; Set-ICal }
                    'gguide'     { Start-Process notepad.exe -ArgumentList "`"$GuideFile`"" }
                    'teamPick'   { Close-Popup; Show-Main; Send-Main @{ type = 'openTeam' } }
                    'teamLogout' { Send-Main @{ type = 'logout' } }
                    'teamSite'   { Start-Process $SiteUrl }
                    'update'     { Check-Update $true }
                    'resetPos'   { Reset-Pos }
                    'uninstall'  { Close-Popup; Uninstall-App }
                }
            }
        }
    }
    function On-PopMessage($m) {
        $p = $script:pop
        if (-not $p) { return }
        switch ([string]$m.cmd) {
            'ready'  {
                $d = $p.Data
                if ($p.Kind -eq 'settings') { $d = @{ ui = $p.Data; host = (Get-Settings) } }
                Send-Pop @{ type = 'popup'; kind = $p.Kind; data = $d; theme = [string]$script:state.Theme }
            }
            'set'    { Apply-Setting ([string]$m.key) $m.value; if ($script:pop) { Send-Pop @{ type = 'settings'; host = (Get-Settings) } } }
            'size'   {
                $h = [int]$m.h
                $maxH = [System.Windows.Forms.Screen]::FromControl($p.F).WorkingArea.Height - [int](20 * $scale)
                $h = [Math]::Max([int](160 * $scale), [Math]::Min($h, $maxH))
                if ($p.F.ClientSize.Height -ne $h) { $p.F.ClientSize = New-Object System.Drawing.Size($p.F.ClientSize.Width, $h) }
            }
            'drag'   { [TLW]::ReleaseCapture() | Out-Null; [TLW]::SendMessage($p.F.Handle, 0xA1, 2, 0) | Out-Null; Save-PopPos $p }
            'close'  { Close-Popup }
            'done'   { Send-Main @{ type = 'popupDone'; kind = $p.Kind; msg = [string]$m.msg; date = [string]$m.date; ids = @($m.ids) }; Close-Popup }
            'gtoken' { Request-GToken ([bool]$m.force) }
            'glogin' { Close-Popup; Start-GoogleLogin }
            'copy'   { try { [System.Windows.Forms.Clipboard]::SetText([string]$m.text) } catch { Write-Log "clipboard: $($_.Exception.Message)" } }
            'open'   { $u = [string]$m.url; if ($u -match '^https://') { Start-Process $u } }
        }
    }

    # ---- 8) 메뉴 (트레이 + 위젯의 ⋯ 버튼) ----
    function New-Item2($parent, $text, [scriptblock]$click) {
        $it = New-Object System.Windows.Forms.ToolStripMenuItem $text
        if ($click) { $it.Add_Click($click) }
        if ($parent -is [System.Windows.Forms.ContextMenuStrip]) { [void]$parent.Items.Add($it) } else { [void]$parent.DropDownItems.Add($it) }
        return $it
    }
    function Add-Sep($parent) { if ($parent -is [System.Windows.Forms.ContextMenuStrip]) { [void]$parent.Items.Add('-') } else { [void]$parent.DropDownItems.Add('-') } }

    $menu = New-Object System.Windows.Forms.ContextMenuStrip
    function Show-Main { $form.Show(); if ($form.WindowState -eq 'Minimized') { $form.WindowState = 'Normal' }; $form.Activate() }
    function Toggle-Main { if ($form.Visible -and $form.WindowState -ne 'Minimized') { $form.Hide() } else { Show-Main } }
    $miShow  = New-Item2 $menu '보이기 / 숨기기' { Toggle-Main }
    [void](New-Item2 $menu '설정…' { Show-Main; Send-Main @{ type = 'openSettings' } })
    Add-Sep $menu
    $miTheme = New-Item2 $menu '테마' $null
    $miLight = New-Item2 $miTheme '라이트' { Set-Theme 'light' }
    $miDark  = New-Item2 $miTheme '다크' { Set-Theme 'dark' }
    $miOpa   = New-Item2 $menu '투명도' $null
    foreach ($p in $OpaSteps) { $it = New-Item2 $miOpa ("{0}%" -f [int]($p * 100)) { Set-Opacity $this.Tag }; $it.Tag = $p }
    Add-Sep $miOpa
    $miHover = New-Item2 $miOpa '마우스 올리면 선명하게' { $script:state.HoverOpaque = -not [bool]$script:state.HoverOpaque; Apply-Opacity; Save-State }
    $miSize  = New-Item2 $menu '크기' $null
    foreach ($p in @(@(0.9, '글자 작게'), @(1.0, '글자 보통'), @(1.15, '글자 크게'))) { $it = New-Item2 $miSize $p[1] { Set-Size $this.Tag }; $it.Tag = $p[0] }
    Add-Sep $miSize
    $miAuto  = New-Item2 $miSize '창 크기 원래대로 (높이 자동)' { Reset-Size }
    $miTop   = New-Item2 $menu '항상 위에 표시' { Toggle-Pin }
    Add-Sep $menu
    $miG     = New-Item2 $menu '내 일정 (구글 캘린더)' $null
    $miGWeb  = New-Item2 $miG '구글 캘린더 열기' { Start-Process 'https://calendar.google.com/calendar/r' }
    Add-Sep $miG
    $miGLog  = New-Item2 $miG '구글 로그인으로 연결' { Start-GoogleLogin }
    $miGIcs  = New-Item2 $miG 'iCal 주소로 연결…' { Set-ICal }
    $miGImp  = New-Item2 $miG '구글 클라우드 설정 파일 불러오기…' { if (Import-GClient) { Start-GoogleLogin } }
    $miGGd   = New-Item2 $miG '설정 방법 보기' { Start-Process notepad.exe -ArgumentList "`"$GuideFile`"" }
    Add-Sep $miG
    $miGOff  = New-Item2 $miG '연결 해제' { Disconnect-Google }
    $miTeam  = New-Item2 $menu '팀 휴가' $null
    [void](New-Item2 $miTeam '내 팀원 설정…' { Show-Main; Send-Main @{ type = 'openTeam' } })
    [void](New-Item2 $miTeam '사이트 열기' { Start-Process $SiteUrl })
    [void](New-Item2 $miTeam '로그아웃' { Send-UI @{ type = 'logout' } })
    $miRef   = New-Item2 $menu '새로고침' { Send-UI @{ type = 'refresh' } }
    $miUpd   = New-Item2 $menu '업데이트 확인' { Check-Update $true }
    Add-Sep $menu
    $miReset = New-Item2 $menu '위치 초기화' { Reset-Pos }
    [void]$menu.Items.Add('-'); $script:exitSep = $menu.Items[$menu.Items.Count - 1]
    $miUninst = New-Item2 $menu 'TeamCal 제거…' { Uninstall-App }
    $miExit  = New-Item2 $menu '위젯 종료' { $script:reallyExit = $true; Close-Popup; Save-State; $tray.Visible = $false; $form.Close() }

    $menu.Add_Opening({
        $miLight.Checked = $script:state.Theme -ne 'dark'; $miDark.Checked = $script:state.Theme -eq 'dark'
        foreach ($i in $miOpa.DropDownItems) { if ($i.Tag -ne $null) { $i.Checked = ([Math]::Abs([double]$i.Tag - [double]$script:state.Opacity) -lt 0.01) } }
        $miHover.Checked = [bool]$script:state.HoverOpaque
        foreach ($i in $miSize.DropDownItems) { if ($i.Tag -ne $null) { $i.Checked = ([Math]::Abs([double]$i.Tag - [double]$script:state.Size) -lt 0.01) } }
        $miAuto.Enabled = ([double]$script:state.W -gt 0 -or [double]$script:state.H -gt 0)
        $miTop.Checked = $form.TopMost
        $miExit.Visible = -not $script:menuFromWidget       # 종료는 트레이 아이콘 메뉴에서만
        $miUninst.Visible = -not $script:menuFromWidget
        $script:exitSep.Visible = -not $script:menuFromWidget
        $miGLog.Checked = $script:state.GMode -eq 'google'
        $miGIcs.Checked = $script:state.GMode -eq 'ical'
        $miGOff.Enabled = [bool]$script:state.GMode
        $miUpd.Text = "업데이트 확인 (지금 v$AppVersion)"
    })

    $tray = New-Object System.Windows.Forms.NotifyIcon
    $script:menuFromWidget = $false
    $menu.Add_Closed({ $script:menuFromWidget = $false })
    $tray.Icon = $trayIcon; $tray.Text = "$AppName (오른쪽 클릭: 메뉴·종료)"; $tray.ContextMenuStrip = $menu; $tray.Visible = $true
    $tray.Add_MouseClick({ if ($_.Button -eq 'Left') { Toggle-Main } })
    $tray.Add_BalloonTipClicked({ Show-Main })

    # ---- 9) 화면에서 온 요청 처리 ----
    function On-UIMessage($m) {
        switch ([string]$m.cmd) {
            'ready'   { Send-Config; if (-not $script:updChecked) { $script:updChecked = $true; Check-Update $false; Fetch-GClientBg } }
            'size'    {
                if ($form.WindowState -ne 'Normal') { return }
                if ($script:resizing) { return }                   # 마우스로 크기를 바꾸는 중에는 그대로
                $h = [int]$m.h
                $h = [Math]::Max([int](120 * $scale), [Math]::Min($h, (Get-MaxH)))      # 정해 둔 높이(또는 화면)까지만, 내용이 적으면 줄어듦
                if ($form.ClientSize.Height -ne $h) { $form.ClientSize = New-Object System.Drawing.Size($form.ClientSize.Width, $h) }
            }
            'drag'    { [TLW]::ReleaseCapture() | Out-Null; [TLW]::SendMessage($form.Handle, 0xA1, 2, 0) | Out-Null; Save-State }
            'resize'  {
                $hit = [int]$m.hit
                if (@(10, 11, 15, 16, 17) -notcontains $hit) { return }
                [TLW]::ReleaseCapture() | Out-Null
                $script:resizing = $true
                [TLW]::SendMessage($form.Handle, 0xA1, $hit, 0) | Out-Null     # 마우스를 놓을 때까지 창 크기 조절
                $script:resizing = $false
                $script:state.W = [Math]::Round($form.Width / $scale)
                if ($hit -ne 10 -and $hit -ne 11) { $script:state.H = [Math]::Round($form.ClientSize.Height / $scale) }
                Send-UI @{ type = 'fixed'; on = ([double]$script:state.H -gt 0); maxH = (Get-MaxH) }
                Save-State
            }
            'hide'    { $form.Hide() }                              # ✕ : 트레이 아이콘으로
            'minimize'{ $form.WindowState = 'Minimized' }           # — : 작업 표시줄로
            'pin'     { Toggle-Pin }
            'opacity' { Next-Opacity }
            'menu'    { $script:menuFromWidget = $true; $menu.Show([System.Windows.Forms.Cursor]::Position) }
            'open'    { $u = [string]$m.url; if ($u -match '^https://') { Start-Process $u } }
            'gtoken'  { Request-GToken ([bool]$m.force) }
            'notify'  {
                # 위젯이 안 보이거나 다른 창을 쓰고 있을 때만 Windows 알림
                $away = (-not $form.Visible) -or ($form.WindowState -eq 'Minimized') -or (-not $form.ContainsFocus)
                if ($away -and $tray) { try { $tray.ShowBalloonTip(6000, [string]$m.title, [string]$m.text, [System.Windows.Forms.ToolTipIcon]::Info) } catch { Write-Log "notify: $($_.Exception.Message)" } }
            }
            'ics'     { Request-ICS }
            'glogin'  { Start-GoogleLogin }
            'gical'   { Set-ICal }
            'gimport' { if (Import-GClient) { Start-GoogleLogin } }
            'gguide'  { Start-Process notepad.exe -ArgumentList "`"$GuideFile`"" }
            'popup'   { Open-Popup ([string]$m.kind) $m.data }
            'glogout' { Disconnect-Google }
            'gauto'   { Set-AutoLogin ([bool]$m.on) }
            'update'  { if ($script:upd) { Do-Update } else { Check-Update $true } }
            'copy'    { try { [System.Windows.Forms.Clipboard]::SetText([string]$m.text) } catch { } }
        }
    }

    $hover = New-Object System.Windows.Forms.Timer
    $hover.Interval = 150
    $hover.Add_Tick({ Apply-Opacity })

    # ---- 10) WebView2 초기화 (환경을 한 번 만들고 기다렸다가 연결) ----
    $wv.Add_CoreWebView2InitializationCompleted({
        param($s, $e)
        if (-not $e.IsSuccess) { Fail-WebView $e.InitializationException '위젯 화면' }
        $cw = $wv.CoreWebView2
        $cw.Settings.IsStatusBarEnabled = $false
        $cw.Settings.AreDefaultContextMenusEnabled = $false
        $cw.Settings.IsZoomControlEnabled = $false
        try { $cw.Settings.IsNonClientRegionSupportEnabled = $true } catch { }   # CSS app-region: drag 로 창 이동
        $cw.SetVirtualHostNameToFolderMapping('tlw.app', $UiDir, [Microsoft.Web.WebView2.Core.CoreWebView2HostResourceAccessKind]::Allow)
        $cw.add_NewWindowRequested({ param($s2, $e2) $e2.Handled = $true; if ($e2.Uri -match '^https://') { Start-Process $e2.Uri } })
        $cw.add_WebMessageReceived({
            param($s2, $e2)
            try { On-UIMessage ($e2.WebMessageAsJson | ConvertFrom-Json) } catch { Write-Log "msg: $($_.Exception.Message)" }
        })
        $wv.ZoomFactor = [double]$script:state.Size
        $cw.Navigate('https://tlw.app/widget.html')
    })
    $envPoll = New-Object System.Windows.Forms.Timer
    $envPoll.Interval = 100
    $envPoll.Add_Tick({
        $t = $script:envTask
        if (-not $t.IsCompleted) { return }
        $envPoll.Stop()
        if ($t.IsFaulted -or $t.IsCanceled) { Fail-WebView ($t.Exception.GetBaseException()) 'WebView2 환경' }
        $script:wvEnv = $t.Result
        $wv.EnsureCoreWebView2Async($t.Result) | Out-Null
    })

    $form.Add_Shown({
        try { $v = 2; [TLW]::DwmSetWindowAttribute($form.Handle, 33, [ref]$v, 4) | Out-Null } catch { }  # Win11 둥근 모서리
        Set-Opacity $script:state.Opacity
        $hover.Start(); $jobTimer.Start(); $updTimer.Start()
        $script:envTask = [Microsoft.Web.WebView2.Core.CoreWebView2Environment]::CreateAsync($null, $DataDir, $null)
        $envPoll.Start()
    })
    $form.Add_Move({ if ($form.Visible) { $script:state.X = $form.Left; $script:state.Y = $form.Top } })
    $script:reallyExit = $false
    $form.Add_FormClosing({
        if (-not $script:reallyExit -and $_.CloseReason -eq 'UserClosing') { $_.Cancel = $true; $form.Hide(); return }
        Close-Popup; Save-State; $tray.Visible = $false; if ($script:gListener) { try { $script:gListener.Stop() } catch { } } })

    [System.Windows.Forms.Application]::Run($form)
    $tray.Dispose()
}
catch {
    Fail "위젯 실행 중 오류가 발생했습니다.`n`n$($_.Exception.Message)`n`n(자세한 기록: $AppDir\error.log)"
}
