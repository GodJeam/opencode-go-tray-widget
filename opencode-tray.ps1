# OpenCode Go - Usage Tray Widget (flyout dark)
$ErrorActionPreference = 'Stop'
$logFile = Join-Path $env:TEMP 'opencode-widget.log'

function Write-Log([string]$msg) {
    Add-Content -LiteralPath $logFile -Value ("[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $msg)
}

try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    Write-Log '--- Widget start ---'

    # Barra di avanzamento arrotondata custom
    if (-not ('OcWidget.UsageBar' -as [type])) {
        Add-Type -ReferencedAssemblies System.Drawing, System.Windows.Forms -TypeDefinition @"
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;

namespace OcWidget {
    public class UsageBar : Control {
        private double _value;
        public double Value {
            get { return _value; }
            set { _value = Math.Max(0, Math.Min(100, value)); Invalidate(); }
        }
        public Color FillColor { get; set; }
        public UsageBar() {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer |
                     ControlStyles.ResizeRedraw | ControlStyles.UserPaint | ControlStyles.SupportsTransparentBackColor, true);
            BackColor = Color.Transparent;
            Height = 10;
        }
        private static GraphicsPath RoundPath(RectangleF r, float rad) {
            var p = new GraphicsPath();
            float d = rad * 2;
            p.AddArc(r.X, r.Y, d, d, 180, 90);
            p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
            p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
            p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
            p.CloseFigure();
            return p;
        }
        protected override void OnPaint(PaintEventArgs e) {
            var g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            var trackRect = new RectangleF(0, Height / 2f - 4f, Width, 8f);
            using (var track = RoundPath(trackRect, 4f))
            using (var tb = new SolidBrush(Color.FromArgb(60, 255, 255, 255)))
                g.FillPath(tb, track);
            if (_value > 0) {
                float w = Math.Max((float)(Width * _value / 100.0), 8f);
                var fillRect = new RectangleF(0, Height / 2f - 4f, w, 8f);
                using (var fill = RoundPath(fillRect, 4f))
                using (var fb = new SolidBrush(FillColor))
                    g.FillPath(fb, fill);
            }
        }
    }
}
"@
    }

    $created = $false
    $mutex = New-Object System.Threading.Mutex($true, 'Local\OpenCodeUsageTrayWidget', [ref]$created)
    if (-not $created) { Write-Log 'Instance already running, exiting'; exit }

    $authPath = Join-Path $env:USERPROFILE '.local\share\opencode\auth.json'

    # Palette
    $bgColor   = [System.Drawing.Color]::FromArgb(32, 33, 36)
    $fgMain    = [System.Drawing.Color]::FromArgb(240, 241, 242)
    $fgMuted   = [System.Drawing.Color]::FromArgb(150, 155, 160)
    $cGreen    = [System.Drawing.Color]::FromArgb(46, 204, 113)
    $cOrange   = [System.Drawing.Color]::FromArgb(230, 126, 34)
    $cRed      = [System.Drawing.Color]::FromArgb(231, 76, 60)

    function Get-PctColor([double]$p) {
        if ($p -ge 80) { return $cRed }
        elseif ($p -ge 50) { return $cOrange }
        else { return $cGreen }
    }

    function New-TrayIcon([int]$percent, [bool]$isError = $false) {
        $bmp = New-Object System.Drawing.Bitmap(16, 16)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.SmoothingMode = 'AntiAlias'
        $color = if ($isError) { [System.Drawing.Color]::Gray } else { Get-PctColor $percent }
        $brush = New-Object System.Drawing.SolidBrush($color)
        $g.FillEllipse($brush, 1, 1, 14, 14)
        $text = if ($percent -ge 100) { '!' } else { [string][Math]::Min($percent, 99) }
        $fontSize = if ($text.Length -ge 2) { 6.5 } else { 8 }
        $font = New-Object System.Drawing.Font('Segoe UI', $fontSize, [System.Drawing.FontStyle]::Bold)
        $sf = New-Object System.Drawing.StringFormat
        $sf.Alignment = 'Center'; $sf.LineAlignment = 'Center'
        $rect = New-Object System.Drawing.RectangleF(0, 1, 16, 15)
        $g.DrawString($text, $font, [System.Drawing.Brushes]::White, $rect, $sf)
        $g.Dispose()
        $hIcon = $bmp.GetHicon()
        $ico = [System.Drawing.Icon]::FromHandle($hIcon)
        $font.Dispose(); $brush.Dispose(); $bmp.Dispose()
        return $ico
    }

    function Get-Usage {
        $key = ((Get-Content $authPath -Raw | ConvertFrom-Json)).('opencode-go').key
        return Invoke-RestMethod -Uri 'https://opencode.ai/zen/go/v1/usage' `
            -Headers @{ Authorization = "Bearer $key" } -TimeoutSec 15
    }

    function Set-IconState([int]$percent, [bool]$isError = $false) {
        $old = $script:icon.Icon
        $script:icon.Icon = New-TrayIcon $percent $isError
        if ($old) { $old.Dispose() }
    }

    function Update-Widget {
        try {
            $data = Get-Usage
            $u = $data.usage
            Set-IconState $u.rolling.percent
            $script:icon.Text = "OpenCode Go | 5h: $($u.rolling.percent)% - Sett: $($u.weekly.percent)% - Mese: $($u.monthly.percent)%"
            $script:lastUsage = $u
            $script:lastUpdate = Get-Date
            $script:ok = $true
            Write-Log "Updated: 5h $($u.rolling.percent)% weekly $($u.weekly.percent)% monthly $($u.monthly.percent)%"
        }
        catch {
            Set-IconState 0 $true
            $script:icon.Text = 'OpenCode Go - Connection error'
            $script:ok = $false
            Write-Log ("UPDATE ERROR: " + $_.Exception.Message)
        }
    }

    function Add-FlyoutRow([System.Windows.Forms.Control]$parent, [int]$y, [string]$name, $u) {
        $color = Get-PctColor ([double]$u.percent)

        $lblName = New-Object System.Windows.Forms.Label
        $lblName.Text = $name
        $lblName.Font = New-Object System.Drawing.Font('Segoe UI', 9.75, [System.Drawing.FontStyle]::Bold)
        $lblName.ForeColor = $fgMain
        $lblName.BackColor = $bgColor
        $lblName.Location = New-Object System.Drawing.Point(20, $y)
        $lblName.AutoSize = $true
        $parent.Controls.Add($lblName)

        $resetStr = ([datetime]$u.resetsAt).ToLocalTime().ToString('dd/MM HH:mm')
        $lblPct = New-Object System.Windows.Forms.Label
        $lblPct.Text = "$($u.percent)%"
        $lblPct.Font = New-Object System.Drawing.Font('Segoe UI', 9.75, [System.Drawing.FontStyle]::Bold)
        $lblPct.ForeColor = $color
        $lblPct.BackColor = $bgColor
        $lblPct.Location = New-Object System.Drawing.Point(232, $y)
        $lblPct.Size = New-Object System.Drawing.Size(68, 18)
        $lblPct.TextAlign = 'MiddleRight'
        $parent.Controls.Add($lblPct)

        $bar = New-Object OcWidget.UsageBar
        $bar.Value = [double]$u.percent
        $bar.FillColor = $color
        $bar.Location = New-Object System.Drawing.Point(20, ($y + 26))
        $bar.Size = New-Object System.Drawing.Size(280, 10)
        $parent.Controls.Add($bar)

        $lblReset = New-Object System.Windows.Forms.Label
        $lblReset.Text = "reset $resetStr"
        $lblReset.Font = New-Object System.Drawing.Font('Segoe UI', 7.75)
        $lblReset.ForeColor = $fgMuted
        $lblReset.BackColor = $bgColor
        $lblReset.Location = New-Object System.Drawing.Point(20, ($y + 40))
        $lblReset.AutoSize = $true
        $parent.Controls.Add($lblReset)
    }

    function Show-Flyout {
        Update-Widget
        if ($script:flyout -and -not $script:flyout.IsDisposed) { return }

        $W = 320; $H = 226
        $f = New-Object System.Windows.Forms.Form
        $f.FormBorderStyle = 'None'
        $f.TopMost = $true
        $f.ShowInTaskbar = $false
        $f.StartPosition = 'Manual'
        $f.BackColor = $bgColor
        $f.Size = New-Object System.Drawing.Size($W, $H)

        # angoli arrotondati
        $path = New-Object System.Drawing.Drawing2D.GraphicsPath
        $r = 12
        $path.AddArc(0, 0, $r, $r, 180, 90)
        $path.AddArc(($W - $r - 1), 0, $r, $r, 270, 90)
        $path.AddArc(($W - $r - 1), ($H - $r - 1), $r, $r, 0, 90)
        $path.AddArc(0, ($H - $r - 1), $r, $r, 90, 90)
        $path.CloseFigure()
        $f.Region = New-Object System.Drawing.Region($path)

        if ($script:ok) {
            $u = $script:lastUsage

            $dot = New-Object System.Windows.Forms.Label
            $dot.Text = [char]9679
            $dot.Font = New-Object System.Drawing.Font('Segoe UI', 8)
            $dot.ForeColor = (Get-PctColor ([double]$u.rolling.percent))
            $dot.BackColor = $bgColor
            $dot.Location = New-Object System.Drawing.Point(20, 16)
            $dot.AutoSize = $true
            $f.Controls.Add($dot)

            $title = New-Object System.Windows.Forms.Label
            $title.Text = "OpenCode Go"
            $title.Font = New-Object System.Drawing.Font('Segoe UI', 11.25, [System.Drawing.FontStyle]::Bold)
            $title.ForeColor = $fgMain
            $title.BackColor = $bgColor
            $title.Location = New-Object System.Drawing.Point(38, 12)
            $title.AutoSize = $true
            $f.Controls.Add($title)

            $updStr = $script:lastUpdate.ToString('HH:mm')
            $lblUpd = New-Object System.Windows.Forms.Label
            $lblUpd.Text = "upd $updStr"
            $lblUpd.Font = New-Object System.Drawing.Font('Segoe UI', 8)
            $lblUpd.ForeColor = $fgMuted
            $lblUpd.BackColor = $bgColor
            $lblUpd.Location = New-Object System.Drawing.Point(232, 19)
            $lblUpd.Size = New-Object System.Drawing.Size(68, 16)
            $lblUpd.TextAlign = 'MiddleRight'
            $f.Controls.Add($lblUpd)

            Add-FlyoutRow $f 52  '5 hours'       $u.rolling
            Add-FlyoutRow $f 110 'Settimanale' $u.weekly
            Add-FlyoutRow $f 168 'Mensile'     $u.monthly
        }
        else {
            $errLbl = New-Object System.Windows.Forms.Label
            $errLbl.Text = "Could not reach the server."
            $errLbl.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)
            $errLbl.ForeColor = $fgMuted
            $errLbl.BackColor = $bgColor
            $errLbl.Location = New-Object System.Drawing.Point(20, 20)
            $errLbl.AutoSize = $true
            $f.Controls.Add($errLbl)
        }

        $f.KeyPreview = $true
        $f.Add_KeyDown({ param($s, $e) if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape) { $s.Close() } })
        $f.Add_Deactivate({ param($s) $s.Close() })

        $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
        $f.Location = New-Object System.Drawing.Point(($wa.Right - $W - 12), ($wa.Bottom - $H - 12))

        $script:flyout = $f
        $f.Show()
        $f.Activate()
        Write-Log 'Flyout shown'
    }

    $context = New-Object System.Windows.Forms.ApplicationContext

    $icon = New-Object System.Windows.Forms.NotifyIcon
    $icon.Text = 'OpenCode Go...'
    $icon.Visible = $true
    $script:icon = $icon
    Set-IconState 0
    Write-Log 'NotifyIcon created and visible'

    $menu = New-Object System.Windows.Forms.ContextMenuStrip
    $itemRefresh = $menu.Items.Add('Refresh')
    $itemRefresh.Add_Click({ Update-Widget })
    $itemDetails = $menu.Items.Add('Details')
    $itemDetails.Add_Click({ Show-Flyout })
    $itemConsole = $menu.Items.Add('Open Console')
    $itemConsole.Add_Click({ Start-Process 'https://opencode.ai/auth' })
    [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    $itemExit = $menu.Items.Add('Exit')
    $itemExit.Add_Click({
        Write-Log 'Exit requested'
        $timer.Stop()
        $icon.Visible = $false
        $icon.Dispose()
        $context.ExitThread()
    })
    $icon.ContextMenuStrip = $menu

    $icon.add_MouseClick({
        param($s, $e)
        if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) { Show-Flyout }
    })

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 300000   # 5 minuti
    $timer.Add_Tick({ Update-Widget })
    $timer.Start()

    Update-Widget
    Write-Log 'Starting message loop'
    [System.Windows.Forms.Application]::Run($context)
    Write-Log 'Message loop ended'
}
catch {
    Write-Log ("FATAL ERROR: " + $_.Exception.Message + " | " + $_.InvocationInfo.PositionMessage)
}



