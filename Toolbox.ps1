Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

function Log([string]$t) { $script:log.AppendText($t + "`r`n") }

function Fmt([double]$b) {
    if ($b -ge 1GB) { return ('{0:N2} GB' -f ($b / 1GB)) }
    if ($b -ge 1MB) { return ('{0:N1} MB' -f ($b / 1MB)) }
    return ('{0:N0} KB' -f ($b / 1KB))
}

function Confirm([string]$msg) {
    $r = [System.Windows.Forms.MessageBox]::Show($msg, 'تأكيد', 'YesNo', 'Question', 'Button1', 'RtlReading,RightAlign')
    return ($r -eq 'Yes')
}

function Get-FolderSize([string]$path) {
    $m = Get-ChildItem -LiteralPath $path -Recurse -Force -File -ErrorAction SilentlyContinue |
        Measure-Object -Property Length -Sum
    if ($m.Sum) { return [double]$m.Sum } else { return 0.0 }
}

# ---------- الأدوات ----------

function Organize-Downloads {
    $dl = Join-Path $env:USERPROFILE 'Downloads'
    if (-not (Test-Path -LiteralPath $dl)) { Log 'مجلد التنزيلات غير موجود.'; return }
    if (-not (Confirm 'سيتم نقل الملفات في مجلد التنزيلات إلى مجلدات حسب النوع (صور، مستندات، ...). لن يُحذف أي ملف. متابعة؟')) { return }

    $map = @{
        'صور'            = @('.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.heic')
        'مستندات'        = @('.pdf', '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx', '.txt', '.csv')
        'فيديو'          = @('.mp4', '.mkv', '.avi', '.mov', '.wmv')
        'صوت'            = @('.mp3', '.wav', '.m4a', '.flac')
        'ملفات مضغوطة'   = @('.zip', '.rar', '.7z', '.tar', '.gz')
        'برامج'          = @('.exe', '.msi', '.msix', '.apk')
    }
    $skip = @('.crdownload', '.part', '.tmp', '.download')
    $count = 0

    foreach ($f in (Get-ChildItem -LiteralPath $dl -File -ErrorAction SilentlyContinue)) {
        $ext = $f.Extension.ToLower()
        if ($skip -contains $ext) { continue }
        $cat = 'أخرى'
        foreach ($k in $map.Keys) { if ($map[$k] -contains $ext) { $cat = $k } }

        $destDir = Join-Path $dl $cat
        if (-not (Test-Path -LiteralPath $destDir)) { New-Item -ItemType Directory -Path $destDir | Out-Null }

        $target = Join-Path $destDir $f.Name
        $i = 1
        while (Test-Path -LiteralPath $target) {
            $target = Join-Path $destDir ('{0} ({1}){2}' -f $f.BaseName, $i, $f.Extension)
            $i++
        }
        try { Move-Item -LiteralPath $f.FullName -Destination $target -ErrorAction Stop; $count++ } catch { }
    }
    Log "تم ترتيب $count ملف في التنزيلات."
}

function Clean-Temp {
    if (-not (Confirm 'سيتم حذف الملفات المؤقتة (Temp). هذا آمن، والملفات المستخدمة حاليًا تُترك. متابعة؟')) { return }
    $before = Get-FolderSize $env:TEMP
    Get-ChildItem -LiteralPath $env:TEMP -Force -ErrorAction SilentlyContinue |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    $after = Get-FolderSize $env:TEMP
    $freed = [Math]::Max(0, $before - $after)
    Log ('تم تنظيف الملفات المؤقتة، وتحرّرت مساحة: ' + (Fmt $freed))
}

function Empty-Recycle {
    if (-not (Confirm 'سيتم تفريغ سلة المحذوفات نهائيًا ولا يمكن التراجع. متابعة؟')) { return }
    Clear-RecycleBin -Force -ErrorAction SilentlyContinue
    Log 'تم تفريغ سلة المحذوفات.'
}

function Restart-Explorer {
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 800
    if (-not (Get-Process -Name explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }
    Log 'تمت إعادة تشغيل شريط المهام وسطح المكتب (يفيد إذا علق ويندوز).'
}

function Fix-Network {
    try {
        Clear-DnsClientCache -ErrorAction Stop
        Log 'تم مسح ذاكرة DNS (يفيد إذا بعض المواقع ما بتفتح).'
    } catch {
        Log 'هذا الزر يحتاج تشغيل البرنامج كمسؤول (كليك يمين > Run as administrator).'
    }
}

function Battery-Report {
    $out = Join-Path ([Environment]::GetFolderPath('Desktop')) 'battery-report.html'
    powercfg /batteryreport /output $out | Out-Null
    if (Test-Path -LiteralPath $out) {
        Start-Process $out
        Log 'تم إنشاء تقرير البطارية على سطح المكتب.'
    } else {
        Log 'لم يتم إنشاء التقرير (قد يكون الجهاز بدون بطارية).'
    }
}

function Open-Startup {
    Start-Process 'ms-settings:startupapps'
    Log 'عطّل البرامج اللي ما تحتاجها عند تشغيل الجهاز لتسريعه.'
}

function System-Info {
    $os = Get-CimInstance Win32_OperatingSystem
    $up = (Get-Date) - $os.LastBootUpTime
    $total = [double]$os.TotalVisibleMemorySize * 1KB
    $free = [double]$os.FreePhysicalMemory * 1KB
    Log ('الرام: المستخدم {0} من {1}' -f (Fmt ($total - $free)), (Fmt $total))
    foreach ($d in (Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3')) {
        Log ('القرص {0} المتبقي {1} من {2}' -f $d.DeviceID, (Fmt ([double]$d.FreeSpace)), (Fmt ([double]$d.Size)))
    }
    Log ('منذ آخر إعادة تشغيل: {0} يوم و {1} ساعة' -f $up.Days, $up.Hours)
}

function Show-PublicIP {
    try {
        $ip = Invoke-RestMethod 'https://api.ipify.org' -TimeoutSec 6
        Log ('آيبيك الحالي: ' + $ip)
    } catch {
        Log 'ما قدرت أعرف الآيبي، تأكد من الإنترنت.'
    }
}

function Big-Files {
    Log 'جاري البحث عن أكبر الملفات، لحظات...'
    [System.Windows.Forms.Application]::DoEvents()
    $paths = @('Downloads', 'Desktop', 'Documents', 'Videos', 'Pictures') |
        ForEach-Object { Join-Path $env:USERPROFILE $_ } |
        Where-Object { Test-Path -LiteralPath $_ }
    $files = foreach ($p in $paths) { Get-ChildItem -LiteralPath $p -Recurse -File -Force -ErrorAction SilentlyContinue }
    $top = $files | Sort-Object Length -Descending | Select-Object -First 10
    if (-not $top) { Log 'ما لقيت ملفات.'; return }
    Log 'أكبر 10 ملفات (احذف اللي ما تحتاجه لتحرير مساحة):'
    foreach ($f in $top) { Log ('{0}   {1}' -f (Fmt ([double]$f.Length)), $f.FullName) }
}

function Kill-Hung {
    $hung = Get-Process | Where-Object { $_.MainWindowHandle -ne 0 -and -not $_.Responding }
    if (-not $hung) { Log 'ما في برامج عالقة حاليًا.'; return }
    $names = ($hung | Select-Object -ExpandProperty ProcessName) -join ', '
    if (Confirm ("البرامج العالقة: $names`nإغلاقها؟ قد تخسر أي تغييرات غير محفوظة فيها.")) {
        $hung | Stop-Process -Force -ErrorAction SilentlyContinue
        Log ('تم إغلاق: ' + $names)
    }
}

function Toggle-Theme {
    $k = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
    $cur = (Get-ItemProperty -Path $k -Name AppsUseLightTheme -ErrorAction SilentlyContinue).AppsUseLightTheme
    $new = 1
    if ($cur -ne 0) { $new = 0 }
    Set-ItemProperty -Path $k -Name AppsUseLightTheme -Value $new -Type DWord
    Set-ItemProperty -Path $k -Name SystemUsesLightTheme -Value $new -Type DWord
    if ($new -eq 1) { Log 'تم التبديل إلى الوضع الفاتح.' } else { Log 'تم التبديل إلى الوضع الداكن.' }
}

function Show-Extensions {
    Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name HideFileExt -Value 0 -Type DWord
    Restart-Explorer
    Log 'صارت امتدادات الملفات ظاهرة (مثل .exe و .pdf)، وهذا يحميك من الملفات المزيفة.'
}

function Update-Apps {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { Log 'أداة winget غير موجودة على هذا الجهاز.'; return }
    if (-not (Confirm 'سيتم تحديث كل البرامج المثبتة اللي لها تحديثات. متابعة؟')) { return }
    Start-Process cmd.exe -ArgumentList '/k winget upgrade --all --accept-source-agreements --accept-package-agreements'
    Log 'فتحت نافذة تحدّث البرامج، اتركها تخلص.'
}

function Repair-System {
    if (-not (Confirm 'سيفحص ويصلح ملفات ويندوز المعطوبة، ويأخذ عدة دقائق وسيطلب صلاحيات المسؤول. متابعة؟')) { return }
    Start-Process cmd.exe -ArgumentList '/k sfc /scannow' -Verb RunAs
    Log 'بدأ الفحص في نافذة منفصلة.'
}

# ---------- الواجهة (تصميم داكن عصري) ----------

function C([string]$hex) { return [System.Drawing.ColorTranslator]::FromHtml($hex) }

function New-RoundPath([int]$w, [int]$h, [int]$r) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $r * 2
    $p.AddArc(0, 0, $d, $d, 180, 90)
    $p.AddArc($w - $d, 0, $d, $d, 270, 90)
    $p.AddArc($w - $d, $h - $d, $d, $d, 0, 90)
    $p.AddArc(0, $h - $d, $d, $d, 90, 90)
    $p.CloseFigure()
    return $p
}

$script:W = 664
$form = New-Object System.Windows.Forms.Form
$form.Text = 'أدوات ويندوز'
$form.ClientSize = New-Object System.Drawing.Size($script:W, 556)
$form.StartPosition = 'CenterScreen'
$form.BackColor = C '#12151C'
$form.ForeColor = C '#E8ECF4'
$form.Font = New-Object System.Drawing.Font('Segoe UI', 10)
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.ShowIcon = $true
$form.Icon = [System.Drawing.Icon]::new("C:\Users\LENOVO\OneDrive\Desktop\Windows Tools(2)\WindowsTools_fixed.ico")
$title = New-Object System.Windows.Forms.Label
$title.Text = 'أدوات ويندوز'
$title.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 22)
$title.ForeColor = C '#FFFFFF'
$title.BackColor = C '#12151C'
$title.TextAlign = 'MiddleRight'
$title.Location = New-Object System.Drawing.Point(20, 14)
$title.Size = New-Object System.Drawing.Size(($script:W - 40), 44)
$form.Controls.Add($title)

$sub = New-Object System.Windows.Forms.Label
$sub.Text = 'اضغط على أي أداة وتتنفذ بضغطة وحدة'
$sub.Font = New-Object System.Drawing.Font('Segoe UI', 10.5)
$sub.ForeColor = C '#8B95A9'
$sub.BackColor = C '#12151C'
$sub.TextAlign = 'MiddleRight'
$sub.Location = New-Object System.Drawing.Point(20, 58)
$sub.Size = New-Object System.Drawing.Size(($script:W - 40), 26)
$form.Controls.Add($sub)

$script:n = 0
function Add-Btn([string]$text, [string]$accent, [scriptblock]$action) {
    $col = $script:n % 3
    $row = [int][Math]::Floor($script:n / 3)
    $x = $script:W - 20 - 200 - $col * 212
    $y = 100 + $row * 58

    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text
    $b.Size = New-Object System.Drawing.Size(200, 48)
    $b.Location = New-Object System.Drawing.Point($x, $y)
    $b.FlatStyle = 'Flat'
    $b.FlatAppearance.BorderSize = 0
    $b.FlatAppearance.MouseOverBackColor = C '#262D3C'
    $b.FlatAppearance.MouseDownBackColor = C '#2E3648'
    $b.UseVisualStyleBackColor = $false
    $b.BackColor = C '#1C212C'
    $b.ForeColor = C '#E8ECF4'
    $b.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10.5)
    $b.TextAlign = 'MiddleRight'
    $b.Padding = New-Object System.Windows.Forms.Padding(8, 0, 20, 0)
    $b.Cursor = [System.Windows.Forms.Cursors]::Hand
    $b.Region = New-Object System.Drawing.Region (New-RoundPath 200 48 10)
    $b.Tag = @{ Action = $action; Accent = (C $accent) }

    $b.Add_Paint({
        param($s, $e)
        $e.Graphics.SmoothingMode = 'AntiAlias'
        $br = New-Object System.Drawing.SolidBrush($s.Tag.Accent)
        $e.Graphics.FillRectangle($br, ($s.Width - 7), 14, 3, ($s.Height - 28))
        $br.Dispose()
    })
    $b.Add_Click({
        param($s, $e)
        try { & $s.Tag.Action } catch { Log ('خطأ: ' + $_.Exception.Message) }
    })
    $form.Controls.Add($b)
    $script:n++
}

$teal = '#2EC4A0'; $blue = '#5B9DFF'; $amber = '#F5B544'; $red = '#FF6B6B'; $purple = '#B388FF'

Add-Btn 'ترتيب التنزيلات'          $teal   { Organize-Downloads }
Add-Btn 'تنظيف الملفات المؤقتة'    $teal   { Clean-Temp }
Add-Btn 'تفريغ سلة المحذوفات'      $red    { Empty-Recycle }
Add-Btn 'أكبر الملفات'              $blue   { Big-Files }
Add-Btn 'معلومات الجهاز'            $blue   { System-Info }
Add-Btn 'إغلاق البرامج العالقة'    $red    { Kill-Hung }
Add-Btn 'إصلاح تعليق الشاشة'       $amber  { Restart-Explorer }
Add-Btn 'مسح DNS للمواقع'           $amber  { Fix-Network }
Add-Btn 'آيبيك الحالي'              $blue   { Show-PublicIP }
Add-Btn 'تقرير البطارية'            $blue   { Battery-Report }
Add-Btn 'برامج البدء'               $teal   { Open-Startup }
Add-Btn 'الوضع الداكن / الفاتح'    $purple { Toggle-Theme }
Add-Btn 'إظهار امتدادات الملفات'   $purple { Show-Extensions }
Add-Btn 'تحديث كل البرامج'         $teal   { Update-Apps }
Add-Btn 'إصلاح ملفات ويندوز'       $amber  { Repair-System }

$logY = 100 + ([int][Math]::Ceiling($script:n / 3)) * 58 + 4
$script:log = New-Object System.Windows.Forms.TextBox
$script:log.Multiline = $true
$script:log.ReadOnly = $true
$script:log.ScrollBars = 'Vertical'
$script:log.BorderStyle = 'None'
$script:log.RightToLeft = 'Yes'
$script:log.BackColor = C '#1C212C'
$script:log.ForeColor = C '#C9D1E0'
$script:log.Font = New-Object System.Drawing.Font('Segoe UI', 10)
$script:log.Location = New-Object System.Drawing.Point(20, $logY)
$script:log.Size = New-Object System.Drawing.Size(($script:W - 40), (556 - $logY - 20))
$form.Controls.Add($script:log)

Log 'جاهز. اختر أداة من الأزرار.'
$form.ShowIcon = $true
$form.Icon = New-Object System.Drawing.Icon("C:\Users\LENOVO\OneDrive\Desktop\Windows Tools(2)\WindowsTools_fixed.ico")
[void]$form.ShowDialog()
