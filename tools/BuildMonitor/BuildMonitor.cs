using System;
using System.IO;
using System.Linq;
using System.Drawing;
using System.Windows.Forms;
using System.Collections.Generic;
using System.Diagnostics;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Runtime.InteropServices;
using System.Text.RegularExpressions;
using System.Globalization;

class Job {
 public string Id, Kind, Status, Log="", Config="", Release="", Reason=""; public DateTime Start, End;
 public bool Running; public double Seconds; public int Number; public DateTime LastOutput;
}
class Snapshot { public List<Job> Jobs=new List<Job>(); public string Activity="No MiSTer activity recorded yet.", Health="", Estimate=""; public bool LiveStateKnown; }
class MonitorForm : Form {
 readonly string root; readonly JavaScriptSerializer json=new JavaScriptSerializer();
 readonly System.Windows.Forms.Timer timer=new System.Windows.Forms.Timer();
 readonly SelectableText health=new SelectableText(), activity=new SelectableText();
 readonly Label heading=new Label();
 readonly List<JobCard> cards=new List<JobCard>();
 readonly Dictionary<string,DateTime> timingRetry=new Dictionary<string,DateTime>();
 readonly Dictionary<string,Job> history=new Dictionary<string,Job>();
 readonly CancellationTokenSource cancel=new CancellationTokenSource();
 readonly PictureBox screenshot=new PictureBox();
 readonly SelectableText screenshotTime=new SelectableText();
 readonly Button capture=new Button(), showBuilds=new Button(), lastScreenshot=new Button();
 bool capturing;
 readonly NotifyIcon tray=new NotifyIcon();
 readonly HashSet<string> notified=new HashSet<string>();
 bool busy; DateTime retryAfter=DateTime.MinValue; int failures;
 readonly Color ink=Color.FromArgb(225,232,244);
 public MonitorForm(string path) {
  root=path;
  try{string saved=File.ReadAllText(Path.Combine(root,"build","monitor","history.json"));foreach(var j in json.Deserialize<Job[]>(saved))history[j.Id]=j;}catch{}
  Text="Zet98 · Build & MiSTer Monitor"; BackColor=Color.FromArgb(18,22,31); ForeColor=ink;
  Font=new Font("Segoe UI",10); ClientSize=new Size(710,715); MinimumSize=new Size(610,610);
  heading.Text="ZET98  /  LIVE WORKBENCH"; heading.Font=new Font("Segoe UI",15,FontStyle.Bold); heading.SetBounds(22,17,480,30); Controls.Add(heading);
  var pin=new CheckBox { Text="Always on top", AutoSize=true, Anchor=AnchorStyles.Top|AnchorStyles.Right }; pin.SetBounds(555,24,145,24); pin.CheckedChanged+=(s,e)=>TopMost=pin.Checked; Controls.Add(pin);
  health.BackColor=BackColor; activity.BackColor=BackColor;
  health.SetBounds(22,53,660,38); health.Anchor=AnchorStyles.Top|AnchorStyles.Left|AnchorStyles.Right; health.ForeColor=Color.FromArgb(153,170,192); Controls.Add(health);
  for(int i=0;i<3;i++){ var c=new JobCard(); c.SetBounds(20,98+i*143,670,133); c.Anchor=AnchorStyles.Top|AnchorStyles.Left|AnchorStyles.Right; Controls.Add(c); cards.Add(c); }
  var title=new Label { Text="Recorded activity · event history",Font=new Font("Segoe UI",11,FontStyle.Bold)}; title.SetBounds(22,541,660,26); Controls.Add(title);
  activity.SetBounds(22,576,660,100); activity.Anchor=AnchorStyles.Top|AnchorStyles.Left|AnchorStyles.Right; activity.ForeColor=ink; Controls.Add(activity);
  var folder=new LinkLabel{Text="Open build files",LinkColor=Color.FromArgb(95,189,247),AutoSize=true}; folder.SetBounds(22,685,140,23); folder.Anchor=AnchorStyles.Left|AnchorStyles.Bottom; folder.LinkClicked+=(s,e)=>Process.Start("explorer.exe",Path.Combine(root,"build")); Controls.Add(folder);
  var note=new Label{Text="Read-only · 10s refresh · no docker stats",AutoSize=true,ForeColor=Color.FromArgb(125,141,163)}; note.SetBounds(330,685,355,22);note.Anchor=AnchorStyles.Right|AnchorStyles.Bottom;Controls.Add(note);
  screenshot.SetBounds(20,126,670,401);screenshot.Anchor=AnchorStyles.Top|AnchorStyles.Left|AnchorStyles.Right;screenshot.SizeMode=PictureBoxSizeMode.Zoom;screenshot.BackColor=Color.Black;screenshot.Visible=false;Controls.Add(screenshot);
  capture.Text="New screenshot";capture.SetBounds(170,679,150,28);capture.Anchor=AnchorStyles.Left|AnchorStyles.Bottom;capture.Click+=async(s,e)=>await CaptureAsync();Controls.Add(capture);
  showBuilds.Text="Show builds";showBuilds.SetBounds(330,679,110,28);showBuilds.Anchor=AnchorStyles.Left|AnchorStyles.Bottom;showBuilds.Click+=(s,e)=>{screenshot.Visible=false;screenshotTime.Visible=false;};Controls.Add(showBuilds);
  screenshotTime.SetBounds(20,98,670,28);screenshotTime.Anchor=AnchorStyles.Top|AnchorStyles.Left|AnchorStyles.Right;screenshotTime.BackColor=BackColor;screenshotTime.ForeColor=ink;screenshotTime.Visible=false;Controls.Add(screenshotTime);
  lastScreenshot.Text="Last screenshot";lastScreenshot.SetBounds(450,679,130,28);lastScreenshot.Anchor=AnchorStyles.Left|AnchorStyles.Bottom;lastScreenshot.Click+=(s,e)=>ShowLastScreenshot();Controls.Add(lastScreenshot);
  note.Visible=false;
  tray.Icon=SystemIcons.Information;tray.Text="Zet98 Monitor";tray.Visible=true;
  tray.BalloonTipClicked+=(s,e)=>{WindowState=FormWindowState.Normal;Activate();};
  FormClosed+=(s,e)=>{tray.Visible=false;tray.Dispose();};
  timer.Interval=10000;timer.Tick+=async(s,e)=>await RefreshAsync();
  Shown+=async(s,e)=>{timer.Start();await RefreshAsync();}; FormClosing+=(s,e)=>{timer.Stop();cancel.Cancel();};
 }
 void ShowScreenshot(string path,string capturedAt){
  using(var image=Image.FromFile(path)){var old=screenshot.Image;screenshot.Image=new Bitmap(image);if(old!=null)old.Dispose();}
  var captured=Date(capturedAt);
  screenshotTime.Text=(captured==DateTime.MinValue?"Saved: "+File.GetLastWriteTime(path).ToString("yyyy-MM-dd HH:mm:ss zzz"):"Captured: "+captured.ToLocalTime().ToString("yyyy-MM-dd HH:mm:ss zzz"));
  screenshotTime.Visible=true;screenshotTime.BringToFront();
  screenshot.Visible=true;screenshot.BringToFront();
 }
 public string ScreenshotState { get { return screenshotTime.Text+"; image="+(screenshot.Image==null?"missing":screenshot.Image.Width+"x"+screenshot.Image.Height)+"; visible="+screenshot.Visible; } }
 public void ShowLastScreenshot(){
  string folder=Path.Combine(root,"build","monitor","captures");
  if(Directory.Exists(folder)){
   foreach(string result in Directory.GetFiles(folder,"result.json",SearchOption.AllDirectories).OrderByDescending(File.GetLastWriteTimeUtc)){
    try{var saved=Obj(Read(result));ShowScreenshot(Val(saved,"path"),Val(saved,"capturedAt"));return;}catch{}
   }
  }
  MessageBox.Show(this,"No saved screenshot is available yet. Use New screenshot to capture one.","Last screenshot");
 }
 public async Task CaptureAsync(){
  if(capturing)return;capturing=true;capture.Enabled=false;capture.Text="Capturing…";
  try{
   while(busy){await Task.Delay(100,cancel.Token);}
   string id=Guid.NewGuid().ToString("N");
   string pwsh=Read(Path.Combine(root,"build","monitor","powershell-path.txt"));
   if(!File.Exists(pwsh))throw new Exception("PowerShell runtime path is missing");
   string script=Path.Combine(root,"scripts","capture-monitor-screenshot.ps1");
   await Task.Run(()=>RunCommand(pwsh,"-NoProfile -File "+Quote(script)+" -CaptureId "+id,cancel.Token,60),cancel.Token);
   var result=Obj(Read(Path.Combine(root,"build","monitor","captures",id,"result.json")));
   ShowScreenshot(Val(result,"path"),Val(result,"capturedAt"));
   if(Val(result,"warning")!="")MessageBox.Show(this,Val(result,"warning"),"Screenshot cleanup");
  }catch(OperationCanceledException){}catch(Exception ex){if(!IsDisposed)MessageBox.Show(this,"Screenshot could not be completed: "+ex.Message+". See the activity feed; no unrelated remote files were deleted.","MiSTer Screenshot");}
  finally{capturing=false;if(!IsDisposed){capture.Enabled=true;capture.Text="New screenshot";}}
 }
 string Read(string p){try{return File.ReadAllText(p).Trim();}catch{return "";}}
 Dictionary<string,object> Obj(string s){return json.Deserialize<Dictionary<string,object>>(s);}
 static string Val(Dictionary<string,object>d,string k){return d.ContainsKey(k)&&d[k]!=null?Convert.ToString(d[k]):"";}
 static DateTime Date(string s){DateTime v;return DateTime.TryParse(s,null,System.Globalization.DateTimeStyles.RoundtripKind,out v)?v.ToUniversalTime():DateTime.MinValue;}
 static string Duration(double s){var t=TimeSpan.FromSeconds(Math.Max(0,s));return ((int)t.TotalHours).ToString("00")+":"+t.Minutes.ToString("00")+":"+t.Seconds.ToString("00");}
 string Kind(string id){return id.Contains("quartus-")?"FPGA build":id.Contains("simulation-")?"Simulation":id.Contains("timequest-")?"Timing check":"Container";}
 void State(Job j,Dictionary<string,object>d){
  j.Start=Date(Val(d,"StartedAt"));j.End=Date(Val(d,"FinishedAt"));j.Running=Val(d,"Running").Equals("True",StringComparison.OrdinalIgnoreCase);
  j.Status=j.Running?(Val(d,"Paused")=="True"?"Paused":"Running"):Val(d,"ExitCode")=="0"?(j.Kind=="FPGA build"?"Compiled · awaiting timing review":"Completed"):"Failed · exit "+Val(d,"ExitCode");
  if(!j.Running&&Val(d,"ExitCode")=="125")j.Status="Failed · STALLED (watchdog stopped Quartus)";
  if(!j.Running&&Val(d,"ExitCode")=="124")j.Status="Failed · time limit reached";
  if(Val(d,"OOMKilled")=="True")j.Status="Failed · memory limit";
  if(Val(d,"Status")=="created")j.Status="Waiting to start";
  j.Seconds=j.Start==DateTime.MinValue?0:((j.Running?DateTime.UtcNow:j.End)-j.Start).TotalSeconds;
 }
 Dictionary<string,string> releases=new Dictionary<string,string>();DateTime releasesRead=DateTime.MinValue;
 // build/hardware/<bundle>/manifest.json maps a Quartus build folder to its release (e.g. B173).
 void ReadReleases(){
  if((DateTime.UtcNow-releasesRead).TotalSeconds<60)return;releasesRead=DateTime.UtcNow;
  try{foreach(var m in Directory.GetFiles(Path.Combine(root,"build","hardware"),"manifest.json",SearchOption.AllDirectories)){
   try{var d=Obj(File.ReadAllText(m));string b=Val(d,"build"),c=Val(d,"core");if(b==""||c=="")continue;
    var rel=System.Text.RegularExpressions.Regex.Match(c,@"_(B\d+)_");releases["zet98-"+b]=rel.Success?rel.Groups[1].Value:Path.GetFileNameWithoutExtension(c);}catch{}
  }}catch{}
 }
 // The line that explains a failed build, instead of Quartus's closing summary.
 static string FailureReason(string log){
  var lines=log.Replace("\r","").Split('\n').Select(l=>l.Trim()).Where(l=>l!="").ToArray();
  var stall=lines.FirstOrDefault(l=>l.StartsWith("Z98_WATCHDOG STALL")||l.StartsWith("Z98_WATCHDOG TIME"));
  if(stall!=null)return stall;
  var err=lines.FirstOrDefault(l=>l.StartsWith("Error (")&&!l.StartsWith("Error (293001)")&&!l.StartsWith("Error (23031)")&&!l.StartsWith("Error (11802)"));
  if(err!=null)return err;
  var any=lines.FirstOrDefault(l=>l.IndexOf("error",StringComparison.OrdinalIgnoreCase)>=0&&!l.StartsWith("Info"));
  return any??"";
 }
 void Local(List<Job> result){
  ReadReleases();
  string build=Path.Combine(root,"build");if(!Directory.Exists(build))return;
  var dirs=Directory.GetDirectories(build).Where(p=>Path.GetFileName(p).StartsWith("quartus-")||Path.GetFileName(p).StartsWith("simulation-")).OrderBy(p=>p).ToArray();
  int number=0;
  foreach(var dir in dirs){ string id="zet98-"+Path.GetFileName(dir);if(id.Contains("quartus-"))number++;
   Job j; if(!history.TryGetValue(id,out j)){j=new Job{Id=id,Kind=Kind(id),Status="Status unavailable"};history[id]=j;}
   j.Number=id.Contains("quartus-")?number:0;
   string rel;if(releases.TryGetValue(id,out rel))j.Release=rel;
   string analysisId=Read(Path.Combine(dir,"timequest-container-name.txt"));
   string analysisState=Read(Path.Combine(dir,"timequest-result.json"));
   if(analysisId!=""&&analysisState!=""){
    try{Job analysis;if(!history.TryGetValue(analysisId,out analysis)){analysis=new Job{Id=analysisId,Kind="Timing check"};history[analysisId]=analysis;}State(analysis,Obj(analysisState));analysis.Config="Build #"+number+" analysis";}catch{}
   }
   j.Config=Read(Path.Combine(dir,"system-clock-mhz.txt"));if(j.Config!="")j.Config+=" MHz · "+Read(Path.Combine(dir,"extended-ram-mb.txt"))+" MB RAM";
   string raw=Read(Path.Combine(dir,"result.json"));if(raw!=""){try{State(j,Obj(raw));}catch{}}
   string timing=Read(Path.Combine(dir,"timing-results.json"));if(!j.Running&&j.Status.StartsWith("Compiled")&&timing!=""){try{var t=Obj(timing);ApplyTiming(j,t);}catch{}}

  }
 }
 // docker logs --timestamps prefixes RFC3339Nano times; .NET parses at most 7 fraction digits.
 static string StripStamps(string raw,out DateTime newest){
  newest=DateTime.MinValue;var lines=new List<string>();
  foreach(string line in raw.Replace("\r","").Split('\n')){
   var m=Regex.Match(line,@"^(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d)(\.\d+)?Z (.*)$");
   if(!m.Success){lines.Add(line);continue;}
   string frac=m.Groups[2].Value;if(frac.Length>8)frac=frac.Substring(0,8);
   DateTime t;if(DateTime.TryParse(m.Groups[1].Value+frac+"Z",null,DateTimeStyles.RoundtripKind,out t)){t=t.ToUniversalTime();if(t>newest)newest=t;}
   lines.Add(m.Groups[3].Value);
  }
  return string.Join("\n",lines.ToArray());
 }
 // B161's longest silent Quartus phase (routing) was 10 minutes. Warn at 15;
 // scripts/quartus-watchdog.sh stops the build at 25 silent minutes.
 public static readonly double StallWarnMinutes=WarnMinutes();
 static double WarnMinutes(){double v;return double.TryParse(Environment.GetEnvironmentVariable("Z98_STALL_WARN_MINUTES"),NumberStyles.Float,CultureInfo.InvariantCulture,out v)&&v>0?v:15;}
 public static double SilentMinutes(Job j){return j.Running&&j.LastOutput!=DateTime.MinValue?(DateTime.UtcNow-j.LastOutput).TotalMinutes:0;}
 public static string StallText(Job j){
  if(j.Log.Contains("Z98_WATCHDOG")||j.Status.Contains("STALLED"))return "WATCHDOG: Quartus stalled and was stopped. Diagnostics: build folder source/Zet98/v17/watchdog/diagnostics.txt";
  double m=SilentMinutes(j);
  return m>=StallWarnMinutes?"WARNING: no output for "+Math.Floor(m*10)/10+" min - possible Quartus hang (watchdog stops it at 25 min)":"";
 }
 static string Tail(string text){return string.Join("\n",text.Replace("\r","").Split('\n').Where(l=>!string.IsNullOrWhiteSpace(l)).Reverse().Take(3).Reverse().Select(l=>l.Trim()).ToArray());}
 string Activity(){
  var dir=Path.Combine(root,"build","monitor-events");if(!Directory.Exists(dir))return "No MiSTer activity recorded yet.";
  var entries=new List<string>();
  foreach(var f in Directory.GetFiles(dir,"*.json").OrderByDescending(File.GetLastWriteTimeUtc).Take(3)){
   try{var d=Obj(Read(f));var start=Date(Val(d,"startedAt"));var end=Date(Val(d,"finishedAt"));string status=Val(d,"status");
    var elapsed=(end==DateTime.MinValue?DateTime.UtcNow:end)-start;
    entries.Add(start.ToLocalTime().ToString("HH:mm:ss")+"  "+status+" · "+Val(d,"title")+"  ["+Duration(elapsed.TotalSeconds)+"]");
   }catch{}
  }
  return entries.Count==0?"No MiSTer activity recorded yet.":string.Join("\n\n",entries.ToArray());
 }
 async Task RefreshAsync(){
  if(busy||capturing||cancel.IsCancellationRequested)return;busy=true;
  try{Snapshot shot=await Task.Run(()=>Poll(),cancel.Token);if(IsDisposed||cancel.IsCancellationRequested)return;
   health.SetLiveText(shot.Health);activity.SetLiveText(shot.Activity);
   for(int i=0;i<3;i++){cards[i].Job=i<shot.Jobs.Count?shot.Jobs[i]:null;cards[i].Estimate="";cards[i].LiveStateKnown=shot.LiveStateKnown;
    if(cards[i].Job!=null){var j=cards[i].Job;var times=history.Values.Where(x=>!x.Running&&x.Kind==j.Kind&&x.Seconds>30&&x.Status.StartsWith(j.Kind=="FPGA build"?"Compiled":"Completed")).Select(x=>x.Seconds).OrderBy(x=>x).ToArray();
     if(j.Running&&shot.LiveStateKnown)cards[i].Estimate=times.Length>=3?"Typical total "+Duration(times[times.Length/2])+" · "+times.Length+" successful runs (estimate)":"Learning duration · needs 3 successful runs";
    }cards[i].Render();}
   foreach(var j in history.Values.Where(x=>x.Kind=="FPGA build"))NotifyStall(j);
  }catch(OperationCanceledException){}catch(Exception ex){health.Text="Monitor error: "+ex.Message;}finally{busy=false;}
 }
 // One notification per build and condition. A watchdog stop is announced
 // only when it happened within the last hour, not for old history.
 void NotifyStall(Job j){
  string text=StallText(j);if(text=="")return;
  bool stopped=!j.Running;string key=j.Id+(stopped?"|stopped":"|warning");
  if(notified.Contains(key))return;notified.Add(key);
  if(stopped&&(j.End==DateTime.MinValue||(DateTime.UtcNow-j.End).TotalMinutes>60))return;
  string title=stopped?"Build #"+j.Number+" stalled - watchdog stopped Quartus":"Build #"+j.Number+" may be hung";
  tray.ShowBalloonTip(30000,title,text,stopped?ToolTipIcon.Error:ToolTipIcon.Warning);
  System.Media.SystemSounds.Exclamation.Play();
  FlashWindow(Handle,true);
 }
 [DllImport("user32.dll")] static extern bool FlashWindow(IntPtr window,bool invert);
 public static Dictionary<string,object> ParseTiming(string summary,string source){
  var matches=Regex.Matches(summary,@"(?m)^Type\s*:\s*(.+)\r?\nSlack\s*:\s*(-?[0-9]+(?:\.[0-9]+)?)");
  if(matches.Count==0)throw new Exception("Timing summary has no recognized checks");
  var checks=new List<Dictionary<string,object>>();double worst=double.MaxValue;int failures=0;
  foreach(Match m in matches){double slack=double.Parse(m.Groups[2].Value,CultureInfo.InvariantCulture);if(slack<0)failures++;worst=Math.Min(worst,slack);checks.Add(new Dictionary<string,object>{{"Type",m.Groups[1].Value.Trim()},{"SlackNs",slack}});}
  return new Dictionary<string,object>{{"Summary",source},{"ReportedTimingViolations",failures},{"WorstSlackNs",worst},{"Checks",checks},{"ReviewedBy","Monitor automatic summary check"}};
 }
 static void ApplyTiming(Job j,Dictionary<string,object> t){
  double worst=Convert.ToDouble(t["WorstSlackNs"],CultureInfo.InvariantCulture);
  j.Status=Val(t,"ReportedTimingViolations")=="0"?"Compiled · timing checks passed":"Compiled · TIMING FAILED ("+worst.ToString("0.000",CultureInfo.InvariantCulture)+" ns)";
 }
 void ReviewTiming(Job j,bool available){
  if(j.Kind!="FPGA build"||j.Running||!j.Status.StartsWith("Compiled"))return;
  string dir=Path.Combine(root,"build",j.Id.Substring("zet98-".Length));
  string output=Path.Combine(dir,"timing-results.json");
  if(File.Exists(output)){try{ApplyTiming(j,Obj(Read(output)));}catch{}return;}
  DateTime retry;if(timingRetry.TryGetValue(j.Id,out retry)&&DateTime.UtcNow<retry)return;
  string summary=Path.Combine(dir,"source","Zet98","v17","output_files","release-Zet98MiSTer.sta.summary");
  try{
   if(!File.Exists(summary)){
    if(!available)return;
    Directory.CreateDirectory(dir);summary=Path.Combine(dir,"monitor-timing.sta.summary");
    RunDocker("cp "+Quote(j.Id+":/project/Zet98/v17/output_files/release-Zet98MiSTer.sta.summary")+" "+Quote(summary),cancel.Token);
   }
   var result=ParseTiming(File.ReadAllText(summary),summary);
   string temporary=output+".monitor.tmp";File.WriteAllText(temporary,json.Serialize(result));
   if(!File.Exists(output))File.Move(temporary,output);else File.Delete(temporary);
   ApplyTiming(j,result);
  }catch{timingRetry[j.Id]=DateTime.UtcNow.AddSeconds(120);j.Status="Compiled · timing review unavailable";}
 }
 string NextStep(){
  var running=history.Values.Where(j=>j.Running).OrderByDescending(j=>j.Start).FirstOrDefault();
  if(running!=null)return "Now: "+running.Kind+" running. Results are not ready yet.";
  var latest=history.Values.Where(j=>j.Kind=="FPGA build").OrderByDescending(j=>j.Start).FirstOrDefault();
  if(latest==null)return "No project job running. Waiting for the next task.";
  if(latest.Status.Contains("TIMING FAILED"))return "No job running. Build #"+latest.Number+" needs code/timing fixes.";
  if(latest.Status.Contains("timing checks passed"))return "No job running. Next: hardware validation; not performed automatically.";
  if(latest.Status.StartsWith("Failed"))return "No job running. Build #"+latest.Number+" failed compilation; needs investigation.";
  return "No job running. Build #"+latest.Number+" awaits timing review; hardware unverified.";
 }
 Snapshot Poll(){
  var shot=new Snapshot();Local(shot.Jobs);shot.Activity=Activity();
  if(DateTime.UtcNow<retryAfter){shot.Health="Docker unavailable · retry "+retryAfter.ToLocalTime().ToString("HH:mm:ss")+" · showing last known state";}
  else try{
   string list=RunDocker("ps -a --format \"{{json .}}\"",cancel.Token);var names=new List<string>();int others=0;var otherNames=new List<string>();
   foreach(string line in list.Split('\n').Where(l=>l.Trim()!="")){
    var d=Obj(line);string name=Val(d,"Names");
    if(name.StartsWith("zet98-quartus-")||name.StartsWith("zet98-simulation-")||name.StartsWith("zet98-timequest-"))names.Add(name);
    else if(Val(d,"State")=="running"){
     others++;Job o;if(!history.TryGetValue(name,out o)){o=new Job{Id=name,Kind="Tests / other container"};history[name]=o;}
     o.Config=Val(d,"Image");o.Running=true;o.Status="Running";otherNames.Add(name);
    }
   }
   // One inspect for all project jobs, then at most three short log calls.
   if(names.Count>0){string raw=RunDocker("inspect "+string.Join(" ",names.Select(n=>Quote(n)).ToArray()),cancel.Token);
    foreach(var item in json.Deserialize<object[]>(raw)){
     var d=(Dictionary<string,object>)item;string name=Val(d,"Name").TrimStart('/');Job j;
     if(!history.TryGetValue(name,out j)){j=new Job{Id=name,Kind=Kind(name)};history[name]=j;}
     State(j,(Dictionary<string,object>)d["State"]);
    }
    foreach(var j in history.Values.Where(j=>names.Contains(j.Id)).OrderByDescending(j=>j.Running).ThenByDescending(j=>j.Start).Take(3)) {string logText=RunDocker("logs --timestamps --tail 3 "+Quote(j.Id),cancel.Token);DateTime last;j.Log=Tail(StripStamps(logText,out last));if(last!=DateTime.MinValue)j.LastOutput=last;}
   }
   foreach(var j in history.Values.Where(j=>j.Kind=="FPGA build"&&!j.Running).OrderByDescending(j=>j.Start).Take(3))ReviewTiming(j,names.Contains(j.Id));
   // Other containers: short log tail and elapsed time; drop them once they exit.
   foreach(var name in otherNames.Take(2)){var o=history[name];
    try{var d=(Dictionary<string,object>)json.Deserialize<object[]>(RunDocker("inspect "+Quote(name),cancel.Token))[0];State(o,(Dictionary<string,object>)d["State"]);}catch{}
    DateTime last;o.Log=Tail(StripStamps(RunDocker("logs --timestamps --tail 3 "+Quote(name),cancel.Token),out last));if(last!=DateTime.MinValue)o.LastOutput=last;}
   foreach(var o in history.Values.Where(j=>j.Kind=="Tests / other container"&&!otherNames.Contains(j.Id)).ToList())history.Remove(o.Id);
   // Failed builds: find the line that explains the failure (fitter, watchdog, synthesis).
   foreach(var j in history.Values.Where(j=>j.Kind=="FPGA build"&&!j.Running&&j.Status.StartsWith("Failed")&&j.Reason=="").OrderByDescending(j=>j.Start).Take(3)){
    string text="";
    string local=Path.Combine(root,"build",j.Id.Replace("zet98-",""),"quartus.log");
    try{if(File.Exists(local))text=File.ReadAllText(local);else if(names.Contains(j.Id))text=RunDocker("logs --tail 4000 "+Quote(j.Id),cancel.Token);}catch{}
    j.Reason=FailureReason(text);if(j.Reason=="")j.Reason="(no error line found)";
   }
   foreach(var j in history.Values.Where(j=>j.Running&&!names.Contains(j.Id)&&j.Kind!="Tests / other container")){j.Running=false;j.Status="Container removed · result unavailable";}
   failures=0;shot.LiveStateKnown=true;shot.Health="Updated "+DateTime.Now.ToString("HH:mm:ss")+" · "+history.Values.Count(j=>j.Running)+" active project jobs · "+others+" other running containers";
  }catch(Exception ex){failures++;retryAfter=DateTime.UtcNow.AddSeconds(Math.Min(120,30*failures));shot.Health="Docker unavailable: "+ex.Message+" · polling paused briefly";}
  Local(shot.Jobs);
  shot.Health+="\n"+(shot.LiveStateKnown?NextStep():"Live build state unknown. Reconnect Docker to verify progress.");
  shot.Jobs=history.Values.OrderByDescending(j=>j.Running).ThenByDescending(j=>j.Start==DateTime.MinValue?DateTime.MinValue:j.Start).Take(3).ToList();
  foreach(var j in shot.Jobs.Where(j=>j.Log=="")){
   string path=Path.Combine(root,"build",j.Id.Replace("zet98-",""),j.Kind=="FPGA build"?"quartus.log":"tests.log");
   try{using(var f=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.ReadWrite)){f.Seek(Math.Max(0,f.Length-16384),SeekOrigin.Begin);using(var r=new StreamReader(f))j.Log=Tail(r.ReadToEnd());}}catch{}
  }
  try{string folder=Path.Combine(root,"build","monitor");Directory.CreateDirectory(folder);File.WriteAllText(Path.Combine(folder,"history.json"),json.Serialize(history.Values.ToArray()));}catch{}
  return shot;
 }
 public static string Quote(string s){return "\""+s.Replace("\"","\\\"")+"\"";}
 public static string RunDocker(string args,CancellationToken token){return RunCommand("docker.exe","--context desktop-linux "+args,token);}
 public static string RunCommand(string executable,string args,CancellationToken token,int timeoutSeconds=6){
  using(var p=new Process())using(var job=new ChildJob()){
   p.StartInfo=new ProcessStartInfo(executable,args){UseShellExecute=false,CreateNoWindow=true,RedirectStandardOutput=true,RedirectStandardError=true};
   try{p.Start();job.Attach(p);var stdout=p.StandardOutput.ReadToEndAsync();var stderr=p.StandardError.ReadToEndAsync();var watch=Stopwatch.StartNew();
    while(!p.WaitForExit(100)){token.ThrowIfCancellationRequested();if(watch.Elapsed.TotalSeconds>timeoutSeconds)throw new TimeoutException("command exceeded "+timeoutSeconds+" seconds");}
    if(!Task.WaitAll(new Task[]{stdout,stderr},1000))throw new TimeoutException("output pipe did not close");
    if(p.ExitCode!=0)throw new Exception("Docker exit "+p.ExitCode);
    return stdout.Result+"\n"+stderr.Result;
   }finally{try{if(!p.HasExited)p.Kill();}catch{}}
  }
 }
}
// Keep the displayed snapshot still while the user selects/copies it.
class SelectableText:RichTextBox {
 public SelectableText(){ReadOnly=true;BorderStyle=BorderStyle.None;DetectUrls=false;WordWrap=false;ScrollBars=RichTextBoxScrollBars.None;HideSelection=false;ShortcutsEnabled=true;
  var menu=new ContextMenuStrip();menu.Items.Add("Copy",null,(s,e)=>Copy());menu.Items.Add("Select all",null,(s,e)=>SelectAll());ContextMenuStrip=menu;
  KeyDown+=(s,e)=>{if(e.Control&&e.KeyCode==Keys.A){SelectAll();e.SuppressKeyPress=true;}};
 }
 public bool SetLiveText(string value){
  // Preserve a selection/active drag, but ordinary focus must not freeze logs.
  if(Text==value||((SelectionLength>0||(Focused&&Control.MouseButtons!=MouseButtons.None))&&Text.Length>0))return false;
  Text=value;Select(0,0);return true;
 }
}
class JobCard:Panel{
 public Job Job;public string Estimate="";public bool LiveStateKnown;
 readonly SelectableText text=new SelectableText();
 readonly Font normal=new Font("Consolas",9),bold=new Font("Segoe UI",11,FontStyle.Bold);
 public JobCard(){BackColor=Color.FromArgb(29,35,47);Padding=new Padding(14,8,12,5);text.Dock=DockStyle.Fill;text.BackColor=BackColor;text.ForeColor=Color.Gainsboro;text.Font=normal;Controls.Add(text);}
 public void Render(){
  if(Job==null){text.SetLiveText("No additional jobs");return;}
  var j=Job;var elapsed=TimeSpan.FromSeconds(Math.Max(0,j.Seconds));string time=((int)elapsed.TotalHours).ToString("00")+elapsed.ToString(@"\:mm\:ss");
  bool stale=j.Running&&!LiveStateKnown;
  string title=j.Kind+(j.Number>0?" #"+j.Number:"")+(j.Release!=""?" · "+j.Release:"")+" · "+(stale?"Status unknown · last seen ":"")+j.Status;
  string stall=MonitorForm.StallText(j);
  string reason=j.Reason!=""&&j.Status.StartsWith("Failed")?"Cause: "+j.Reason:"";
  const string stamp="yyyy-MM-dd HH:mm:ss";
  string when=j.Start==DateTime.MinValue?"":"Started "+j.Start.ToLocalTime().ToString(stamp)+
      (!j.Running&&j.End!=DateTime.MinValue&&j.End>=j.Start?"   Ended "+j.End.ToLocalTime().ToString(stamp):"");
  string content=title+"\n"+j.Config+(stale?"   Last elapsed ":"   Elapsed ")+time+"   "+Estimate+"\n"+(when!=""?when+"\n":"")+j.Id+"\n"+(stall!=""?stall+"\n":"")+(reason!=""?reason:j.Log);
  if(!text.SetLiveText(content))return;
  text.SelectAll();text.SelectionFont=normal;text.SelectionColor=Color.Gainsboro;
  text.Select(0,title.Length);text.SelectionFont=bold;
  text.SelectionColor=stale?Color.FromArgb(238,193,111):j.Status.Contains("Failed")||j.Status.Contains("FAILED")?Color.FromArgb(255,129,133):j.Running?Color.FromArgb(93,204,246):Color.FromArgb(141,213,170);
  if(reason!=""){int at=content.IndexOf(reason);text.Select(at,reason.Length);text.SelectionFont=bold;text.SelectionColor=Color.FromArgb(255,129,133);}
  if(stall!=""){int at=content.IndexOf(stall);text.Select(at,stall.Length);text.SelectionFont=bold;text.SelectionColor=stall.StartsWith("WATCHDOG")?Color.FromArgb(255,129,133):Color.FromArgb(238,193,111);}
  text.Select(0,0);
 }
 protected override void Dispose(bool disposing){if(disposing){normal.Dispose();bold.Dispose();}base.Dispose(disposing);}
}
// Closing the job handle terminates only this monitor's command and its children.
class ChildJob:IDisposable {
 IntPtr handle;
 [StructLayout(LayoutKind.Sequential)] struct Basic{public long a,b;public uint flags;public UIntPtr min,max;public uint active;public UIntPtr affinity;public uint priority,schedule;}
 [StructLayout(LayoutKind.Sequential)] struct IO{public ulong a,b,c,d,e,f;}
 [StructLayout(LayoutKind.Sequential)] struct Extended{public Basic basic;public IO io;public UIntPtr a,b,c,d;}
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode)]static extern IntPtr CreateJobObject(IntPtr attr,string name);
 [DllImport("kernel32.dll")]static extern bool SetInformationJobObject(IntPtr h,int cls,ref Extended info,int len);
 [DllImport("kernel32.dll")]static extern bool AssignProcessToJobObject(IntPtr h,IntPtr process);
 [DllImport("kernel32.dll")]static extern bool CloseHandle(IntPtr h);
 public ChildJob(){handle=CreateJobObject(IntPtr.Zero,null);var info=new Extended();info.basic.flags=0x2000;if(handle==IntPtr.Zero||!SetInformationJobObject(handle,9,ref info,Marshal.SizeOf(info)))throw new Exception("Cannot create bounded process job");}
 public void Attach(Process p){if(!AssignProcessToJobObject(handle,p.Handle))throw new Exception("Cannot contain Docker client process");}
 public void Dispose(){if(handle!=IntPtr.Zero){CloseHandle(handle);handle=IntPtr.Zero;}}
}
static class Program {
 [DllImport("user32.dll")] static extern bool PrintWindow(IntPtr window, IntPtr dc, uint flags);
 [STAThread]static void Main(string[] args){
  if(args.Length>1&&args[0]=="--timing-check"){
   var result=MonitorForm.ParseTiming(File.ReadAllText(args[1]),args[1]);
   File.WriteAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"timing-check.json"),new JavaScriptSerializer().Serialize(result));return;
  }
  if(args.Length>0&&args[0]=="--hang"){File.WriteAllText(args[1],Process.GetCurrentProcess().Id.ToString());Thread.Sleep(30000);return;}
  if(args.Length>0&&args[0]=="--self-test"){
   var output=Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"self-test.txt");
   try{
    MonitorForm.RunDocker("version --format \"{{.Client.Version}}\"",CancellationToken.None);
    string pidFile=Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"test-child.pid");
    for(int mode=0;mode<2;mode++){
     using(var cts=new CancellationTokenSource()){
      if(mode==1)cts.CancelAfter(500);
      bool rejected=false;
      try{MonitorForm.RunCommand(Application.ExecutablePath,"--hang "+MonitorForm.Quote(pidFile),cts.Token);}
      catch(TimeoutException){rejected=mode==0;}
      catch(OperationCanceledException){rejected=mode==1;}
      if(!rejected)throw new Exception("Timeout/cancellation was not enforced");
      int pid=int.Parse(File.ReadAllText(pidFile));
      try{using(var child=Process.GetProcessById(pid)){if(!child.WaitForExit(3000))throw new Exception("Orphan child process "+pid);}}catch(ArgumentException){}
     }
    }
    File.WriteAllText(output,"PASS: bounded Docker query; six-second timeout; cancellation; no child processes left behind");
   }catch(Exception e){File.WriteAllText(output,"FAIL: "+e);}return;
  }
  string root=args.Length>0?args[0]:Path.GetFullPath(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"..",".."));
  if(!Directory.Exists(Path.Combine(root,"scripts"))){MessageBox.Show("Pass the PC98_MiSTer project folder as the first argument.");return;}
  Application.EnableVisualStyles();Application.SetCompatibleTextRenderingDefault(false);var form=new MonitorForm(root);
  if(args.Length>1&&args[1]=="--preview"){
   var capture=new System.Windows.Forms.Timer{Interval=12000};capture.Tick+=(s,e)=>{capture.Stop();using(var image=new Bitmap(form.Width,form.Height)){using(var g=Graphics.FromImage(image)){var dc=g.GetHdc();try{PrintWindow(form.Handle,dc,2);}finally{g.ReleaseHdc(dc);}}image.Save(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"preview.png"));}form.Close();};capture.Start();
  }
  if(args.Contains("--last-preview"))form.Shown+=(s,e)=>{form.ShowLastScreenshot();File.WriteAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"last-view.txt"),form.ScreenshotState);};
  if(args.Contains("--capture-preview"))form.Shown+=async(s,e)=>await form.CaptureAsync();
  Application.Run(form);
 }
}
