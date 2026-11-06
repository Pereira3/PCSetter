#region 1. CONFIGURATION
# ============================================================================
# 1. CONFIGURATION
#    Everything you may want to change lives here: global settings and the list of apps.
#    Nothing in this section does any work; it only sets values and data.
# ============================================================================

# ---- 1.1  Settings -------------------------------------------------------
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$VerifyOnly = ($env:PCSetter_VERIFY -eq '1')
$LogPath    = Join-Path $env:TEMP 'pcsetter.log'
$WorkDir    = Join-Path $env:TEMP ('PCSetter-' + [guid]::NewGuid().ToString('N'))
$Dot        = [string][char]0x00B7
$BadgeSize  = 40
$ProjectUrl = 'https://get.activated.win/' 


# ---- 1.2  App catalog -------------------------------------------------------
$Apps = @(
    @{ Id='mas'; Name='Microsoft Activation Scripts (MAS)'; Icon='terminal'; Category='Windows'; Site='massgrave.dev'
       Url=$ProjectUrl
       Hosts=@('get.activated.win')
       Kind='irm'; Tag='Runs first' }

    @{ Id='brave'; Name='Brave'; Icon='globe'; Category='Browser'; Site='brave.com'
       Url='https://laptop-updates.brave.com/latest/winx64'; File='BraveBrowserSetup.exe'
       Hosts=@('brave.com','bravesoftware.com'); Signer='Brave Software, Inc.'
       DetectName='^Brave$'
       DetectPaths=@("$env:ProgramFiles\BraveSoftware\Brave-Browser\Application\brave.exe", "${env:ProgramFiles(x86)}\BraveSoftware\Brave-Browser\Application\brave.exe", "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\Application\brave.exe")
       Kind='exe'; Args='/silent /install'; Tag='Debloated preset'; Pre='BravePolicies' }

    @{ Id='spotify'; Name='Spotify'; Icon='note'; Category='Music'; Site='spotify.com'
       Url='https://download.scdn.co/SpotifyFullSetup.exe'; File='SpotifyFullSetup.exe'
       Hosts=@('scdn.co','spotify.com'); Signer='Spotify AB'
       DetectName='^Spotify$'
       Kind='exe'; Unelevated=$true; Detect=(Join-Path $env:APPDATA 'Spotify\Spotify.exe') }

    @{ Id='steam'; Name='Steam'; Icon='gamepad'; Category='Games'; Site='steampowered.com'
       Urls=@('https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe','https://cdn.fastly.steamstatic.com/client/installer/SteamSetup.exe'); File='SteamSetup.exe'
       Hosts=@('steamstatic.com','steampowered.com'); Signer='Valve Corp.'
       DetectName='^Steam$'
       DetectPaths=@("${env:ProgramFiles(x86)}\Steam\steam.exe", "$env:ProgramFiles\Steam\steam.exe")
       Kind='exe'; Args='/S' }

    @{ Id='epic'; Name='Epic Games Launcher'; Icon='gamepad'; Category='Games'; Site='epicgames.com'
       Url='https://launcher-public-service-prod06.ol.epicgames.com/launcher/api/installer/download/EpicGamesLauncherInstaller.msi'
       File='EpicGamesLauncherInstaller.msi'
       Hosts=@('epicgames.com'); Signer='Epic Games, Inc.'
       DetectName='^Epic Games Launcher$'
       DetectPaths=@("${env:ProgramFiles(x86)}\Epic Games\Launcher\Portal\Binaries\Win64\EpicGamesLauncher.exe", "${env:ProgramFiles(x86)}\Epic Games\Launcher\Portal\Binaries\Win32\EpicGamesLauncher.exe")
       Kind='msi' }

    @{ Id='lol'; Name='League of Legends'; Icon='gamepad'; Category='Games'; Site='leagueoflegends.com'
       Url="https://lol.secure.dyn.riotcdn.net/channels/public/x/installer/current/live.euw.exe"
       File="live.euw.exe"
       Hosts=@('riotcdn.net','riotgames.com','leagueoflegends.com'); Signer='Riot Games, Inc.'
       DetectName='^League of Legends'
       DetectPaths=@("$env:SystemDrive\Riot Games\League of Legends\LeagueClient.exe")
       Kind='exe'; Interactive=$true }
)





#region 2. START-UP CHECKS
# ============================================================================
# 2. START-UP CHECKS
#    Runs before anything is shown: makes sure we are an administrator, loads the WPF
#    libraries, installs a global error dialog and starts the log file.
# ============================================================================

# ---- 2.1  Administrator check --------------------------------------------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    # A console window closes the moment the script ends, so report this in a dialog that stays on screen.
    Add-Type -AssemblyName PresentationFramework
    if ($PSCommandPath) {
        $answer = [Windows.MessageBox]::Show(
            "This installer needs administrator rights to run correctly.`nDo you want to give the rights for administrator access?",
            'PCSetter', 'YesNo', 'Question')
        if ($answer -eq 'Yes') {
            try {
                Start-Process -FilePath powershell.exe -Verb RunAs -WindowStyle Hidden -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
            } catch { }   # the permission prompt was declined
        }
    } else {
        [void][Windows.MessageBox]::Show(
            "This installer needs administrator rights.`n`nClose this window, open PowerShell with 'Run as administrator', and run the command again.",
            'PCSetter', 'OK', 'Warning')
    }
    return
}


# ---- 2.2  Load WPF, error dialog, log file -------------------------------
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Net.Http

# Show unexpected start-up errors in a dialog instead of a console that vanishes.
trap {
    try { [void][Windows.MessageBox]::Show("The installer hit an error:`n`n$($_.Exception.Message)", 'PCSetter', 'OK', 'Error') } catch { }
    break
}
Set-Content -Path $LogPath -Value ('PCSetter started {0:s} (verify-only: {1})' -f (Get-Date), $VerifyOnly)





# ============================================================================
# 3. GENERAL HELPERS
#    Small building blocks used by every other section.
# ============================================================================


# ---- 3.1  Logging and utilities ------------------------------------------
function Write-Log($m) { Add-Content -Path $LogPath -Value ('{0:s} {1}' -f (Get-Date), $m) }
function Esc($s) { [Security.SecurityElement]::Escape([string]$s) }
function Brush($hex) { (New-Object Windows.Media.BrushConverter).ConvertFromString($hex) }
function Update-UI { $window.Dispatcher.Invoke([Action]{}, [Windows.Threading.DispatcherPriority]::Background) }
function Get-Err($e) { if ($e.Exception.InnerException) { $e.Exception.InnerException.Message } else { $e.Exception.Message } }

function Set-RoundedButtonStyle($targetWindow) {
    $style = New-Xaml @'
<Style xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
       xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
       TargetType="{x:Type Button}">
  <Setter Property="Background" Value="White"/>
  <Setter Property="Foreground" Value="#1B1B1B"/>
  <Setter Property="BorderBrush" Value="#BDBDBD"/>
  <Setter Property="BorderThickness" Value="1"/>
  <Setter Property="Padding" Value="12,0"/>
  <Setter Property="Cursor" Value="Hand"/>
  <Setter Property="Template">
    <Setter.Value>
      <ControlTemplate TargetType="{x:Type Button}">
        <Border x:Name="Chrome" Background="{TemplateBinding Background}"
                BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}"
                CornerRadius="6" SnapsToDevicePixels="True">
          <ContentPresenter HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}"
                            VerticalAlignment="{TemplateBinding VerticalContentAlignment}"
                            Margin="{TemplateBinding Padding}" RecognizesAccessKey="True"/>
        </Border>
        <ControlTemplate.Triggers>
          <Trigger Property="IsMouseOver" Value="True">
            <Setter TargetName="Chrome" Property="BorderBrush" Value="#0F6CBD"/>
          </Trigger>
          <Trigger Property="IsPressed" Value="True">
            <Setter TargetName="Chrome" Property="Opacity" Value="0.82"/>
          </Trigger>
          <Trigger Property="IsEnabled" Value="False">
            <Setter TargetName="Chrome" Property="Opacity" Value="0.5"/>
          </Trigger>
          <Trigger Property="IsKeyboardFocused" Value="True">
            <Setter TargetName="Chrome" Property="BorderBrush" Value="#0F6CBD"/>
          </Trigger>
        </ControlTemplate.Triggers>
      </ControlTemplate>
    </Setter.Value>
  </Setter>
</Style>
'@
    $targetWindow.Resources.Add([Windows.Controls.Button], $style)
}

function Set-SlimScrollbarStyle($targetWindow) {
    $style = New-Xaml @'
<Style xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
       xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
       TargetType="{x:Type ScrollBar}">
  <Setter Property="Width" Value="8"/>
  <Setter Property="MinWidth" Value="8"/>
  <Setter Property="Background" Value="Transparent"/>
  <Setter Property="Template">
    <Setter.Value>
      <ControlTemplate TargetType="{x:Type ScrollBar}">
        <Grid Background="Transparent">
          <Track x:Name="PART_Track" Orientation="{TemplateBinding Orientation}" IsDirectionReversed="True"
                 Minimum="{TemplateBinding Minimum}" Maximum="{TemplateBinding Maximum}"
                 Value="{TemplateBinding Value}" ViewportSize="{TemplateBinding ViewportSize}">
            <Track.Thumb>
              <Thumb>
                <Thumb.Template>
                  <ControlTemplate TargetType="{x:Type Thumb}">
                    <Border Background="#BDBDBD" CornerRadius="3" Margin="1"/>
                  </ControlTemplate>
                </Thumb.Template>
              </Thumb>
            </Track.Thumb>
          </Track>
        </Grid>
      </ControlTemplate>
    </Setter.Value>
  </Setter>
</Style>
'@
    $targetWindow.Resources.Add([Windows.Controls.Primitives.ScrollBar], $style)
}




#region 4. SYSTEM CHECKS
# ============================================================================
# 4. SYSTEM CHECKS
#    Everything the installer asks Windows or the installer files: is the app already
#    installed, is the signature genuine, which Brave policies to write.
# ============================================================================
 

# ---- 4.1  Already-installed detection ------------------------------------
# Names of everything listed in "Apps & features" (machine-wide, 32-bit on 64-bit Windows, and current user).
function Get-InstalledNames {
    $roots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $names = @()
    foreach ($r in $roots) {
        try { $names += @(Get-ItemProperty -Path $r -ErrorAction SilentlyContinue | ForEach-Object { $_.DisplayName }) } catch { }
    }
    return @($names | Where-Object { $_ })
}

# Returns a short text saying how the app was found (used in the log), or $null when it is not installed.
function Test-AppInstalled($app) {
    if ($app.Kind -eq 'irm') { return $null }      # a script, not a program: it can always be run
    $paths = @($app.DetectPaths)
    if ($app.Detect) { $paths += $app.Detect }
    foreach ($p in $paths) {
        if ($p -and (Test-Path -LiteralPath $p)) { return "found $p" }
    }
    if ($app.DetectName) {
        foreach ($n in $script:InstalledNames) {
            if ($n -match $app.DetectName) { return "listed as '$n'" }
        }
    }
    return $null
}

$ns = 'xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'
function New-Xaml([string]$x) { [Windows.Markup.XamlReader]::Load([Xml.XmlReader]::Create((New-Object IO.StringReader $x))) }

# Built-in vector icons (24 x 24 grid). Add your own: name -> one or more <Path> elements.
# F1 = fill nonzero, F0 = even-odd (holes). Use Stroke="..." for outline-only shapes.
$IconData = @{
    globe   = '<Path Stroke="#0B5CA5" StrokeThickness="1.6" StrokeLineJoin="Round" Data="M12,2 A10,10 0 1 1 12,22 A10,10 0 1 1 12,2 Z M2,12 H22 M12,2 C6,7 6,17 12,22 M12,2 C18,7 18,17 12,22 M4,7 H20 M4,17 H20"/>'
    note    = '<Path Fill="#0B5CA5" Data="F1 M13,3 H14.6 V17 H13 Z M14.6,3 C14.6,8 20.5,8 20.5,14.5 C18.5,11.5 16.5,11 14.6,10.5 Z M6.5,17 A3.6,2.9 0 1 1 13.7,17 A3.6,2.9 0 1 1 6.5,17 Z"/>'
    terminal = '<Path Stroke="#0B5CA5" StrokeThickness="1.6" StrokeLineJoin="Round" Data="M4,4 H20 A2,2 0 0 1 22,6 V18 A2,2 0 0 1 20,20 H4 A2,2 0 0 1 2,18 V6 A2,2 0 0 1 4,4 Z"/><Path Stroke="#0B5CA5" StrokeThickness="1.8" StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round" Data="M6.5,9.5 L10,12.5 L6.5,15.5 M12.5,15.5 H17.5"/>'
    gamepad = '<Path Fill="#0B5CA5" Data="F0 M7,6.5 H17 C20.6,6.5 22.6,9.6 22.1,14.2 L21.4,18.2 C21.1,20 19,20.7 17.8,19.3 L15.6,16.8 H8.4 L6.2,19.3 C5,20.7 2.9,20 2.6,18.2 L1.9,14.2 C1.4,9.6 3.4,6.5 7,6.5 Z M6.2,10 H7.8 V11.2 H9 V12.8 H7.8 V14 H6.2 V12.8 H5 V11.2 H6.2 Z M15,10.6 A0.9,0.9 0 1 0 16.8,10.6 A0.9,0.9 0 1 0 15,10.6 Z M17.4,12.9 A0.9,0.9 0 1 0 19.2,12.9 A0.9,0.9 0 1 0 17.4,12.9 Z"/>'
}

function Get-BadgeXaml($app) {
    $iconPx = [int]($BadgeSize * 0.6)
    $shape = $IconData[$app.Icon]
    if ($shape) {
        $inner = '<Viewbox Width="{0}" Height="{0}" HorizontalAlignment="Center" VerticalAlignment="Center"><Canvas Width="24" Height="24">{1}</Canvas></Viewbox>' -f $iconPx, $shape
    } else {
        # no icon defined for this app: fall back to its first two letters
        $letters = Esc ($app.Name.Substring(0, [Math]::Min(2, $app.Name.Length)))
        $inner = '<TextBlock Text="{0}" FontSize="{1}" FontWeight="SemiBold" Foreground="#0B5CA5" HorizontalAlignment="Center" VerticalAlignment="Center"/>' -f $letters, [int]($BadgeSize * 0.4)
    }
    return ('<Border Width="{0}" Height="{0}" CornerRadius="8" Background="#E8F1FA" Margin="0,0,12,0" VerticalAlignment="Center">{1}</Border>' -f $BadgeSize, $inner)
}


# ---- 4.2  Signature verification -----------------------------------------
function Get-SignerName($cert) {
    if ($cert.Subject -match 'CN=(?:"((?:[^"]|"")+)"|([^,]+))') {
        if ($Matches[1]) { return ($Matches[1] -replace '""', '"') }
        return $Matches[2].Trim()
    }
    return $cert.Subject
}

function Test-AppSignature($path, $expected) {
    $sig = Get-AuthenticodeSignature -FilePath $path
    if ($sig.Status -ne 'Valid') {
        return @{ Ok = $false; Signer = $null; Thumb = $null; Why = "Signature is not valid ($($sig.Status))" }
    }
    $name = Get-SignerName $sig.SignerCertificate
    $ok = ($name -ceq $expected)
    $why = ''
    if (-not $ok) { $why = "Signed by '$name', expected '$expected'" }
    return @{ Ok = $ok; Signer = $name; Thumb = $sig.SignerCertificate.Thumbprint; Why = $why }
}


# ---- 4.3  Brave policies -------------------------------------------------
function Set-BravePolicies {
    $key = 'HKLM:\SOFTWARE\Policies\BraveSoftware\Brave'
    New-Item -Path $key -Force | Out-Null
    $policies = [ordered]@{
        BraveRewardsDisabled = 1; BraveNewsDisabled = 1; BraveTalkDisabled = 1; SyncDisabled = 1
        BraveWalletDisabled  = 1; BraveVPNDisabled  = 1; BraveAIChatEnabled = 0; TorDisabled  = 1
    }
    foreach ($k in $policies.Keys) {
        Set-ItemProperty -Path $key -Name $k -Type DWord -Value $policies[$k]
    }
    Write-Log "Brave: $($policies.Count) policies written to $key"
    return $policies.Count
}





# ============================================================================
# 5. USER INTERFACE
#    Icons, the window layout (XAML), the shared UI state, and the builders for the
#    rows shown on the picker and progress screens.
# ============================================================================
 

# ---- 5.1  Window layout (XAML) and control handles -----------------------
$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="PCSetter" Width="760" Height="560" MinWidth="560" MinHeight="420"
        WindowStartupLocation="CenterScreen" Background="#F3F3F3" FontFamily="Segoe UI" UseLayoutRounding="True">
  <Window.Resources>
    <!-- Look of the check box of an app that is already installed: filled blue, white tick, small lock badge. -->
    <ControlTemplate x:Key="LockedCheck" TargetType="CheckBox">
      <Grid Background="Transparent">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>
        <Canvas Width="24" Height="24" VerticalAlignment="Center">
          <Border Canvas.Left="0" Canvas.Top="0" Width="20" Height="20" CornerRadius="4" Background="#0F6CBD"/>
          <Path Stroke="White" StrokeThickness="2" StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round" Data="M5,10.5 L8.7,14 L15,6.5"/>
          <Border Canvas.Left="11" Canvas.Top="11" Width="13" Height="13" CornerRadius="6.5" Background="White" BorderBrush="#0F6CBD" BorderThickness="1.2">
            <Viewbox Width="7" Height="7" HorizontalAlignment="Center" VerticalAlignment="Center">
              <Canvas Width="24" Height="24">
                <Path Fill="#0F6CBD" Data="M5,11 H19 V22 H5 Z"/>
                <Path Stroke="#0F6CBD" StrokeThickness="3.2" Data="M8,11 V7.5 A4,4 0 0 1 16,7.5 V11"/>
              </Canvas>
            </Viewbox>
          </Border>
        </Canvas>
        <ContentPresenter Grid.Column="1" Margin="{TemplateBinding Padding}" HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}" VerticalAlignment="{TemplateBinding VerticalContentAlignment}"/>
      </Grid>
    </ControlTemplate>
  </Window.Resources>
  <Grid>
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="64"/>
    </Grid.RowDefinitions>
    <StackPanel Grid.Row="0" Margin="24,18,24,8">
      <TextBlock x:Name="Heading" FontSize="20" FontWeight="SemiBold" Foreground="#1B1B1B"/>
      <TextBlock x:Name="Subheading" FontSize="13" Foreground="#5C5C5C" TextWrapping="Wrap" Margin="0,4,0,0"/>
    </StackPanel>
    <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" Margin="24,0,24,0">
      <StackPanel x:Name="List" Margin="0,0,10,0"/>
    </ScrollViewer>
    <Border Grid.Row="2" Background="White" BorderBrush="#E1E1E1" BorderThickness="0,1,0,0">
      <DockPanel Margin="24,0">
        <StackPanel DockPanel.Dock="Right" Orientation="Horizontal" VerticalAlignment="Center">
          <Button x:Name="BtnSecondary" Content="Clear" MinWidth="88" Height="40" Margin="0,0,10,0" Padding="14,0" Background="White" BorderBrush="#BDBDBD"/>
          <Button x:Name="BtnPrimary" Content="Install" MinWidth="112" Height="40" Background="#0F6CBD" Foreground="White" FontWeight="SemiBold" BorderThickness="0"/>
        </StackPanel>
        <TextBlock x:Name="FooterText" VerticalAlignment="Center" FontSize="13" Foreground="#5C5C5C" TextTrimming="CharacterEllipsis"/>
      </DockPanel>
    </Border>
  </Grid>
</Window>
'@
$window       = New-Xaml $xaml
Set-RoundedButtonStyle $window
Set-SlimScrollbarStyle $window
$Heading      = $window.FindName('Heading')
$Subheading   = $window.FindName('Subheading')
$List         = $window.FindName('List')
$BtnSecondary = $window.FindName('BtnSecondary')
$BtnPrimary   = $window.FindName('BtnPrimary')
$FooterText   = $window.FindName('FooterText')


# ---- 5.3  UI state -------------------------------------------------------
$script:Phase   = 'pick'      # pick -> run -> done
$script:Cancel  = $false
$script:Rows    = @{}
$script:Results = @{}
$Checks         = @{}


# ---- 5.4  Row builders ---------------------------------------------------
function New-PickRow($app, $locked) {
    $site = Esc $app.Site
    if ($app.Kind -eq 'irm') { $detail = 'Runs first; opens an interactive PowerShell window' }
    else                     { $detail = "Signer: $($app.Signer)" }
    $detail = Esc $detail
    $tag = ''
    $tip = ''
    if ($locked) {
        $tag = '<Border Grid.Column="2" Background="#0F6CBD" CornerRadius="10" Padding="10,2" VerticalAlignment="Center"><TextBlock Text="Installed" FontSize="12" Foreground="White"/></Border>'
        $tip = 'ToolTip="Already installed on this PC"'
    }
    elseif ($app.Tag) {
        $tag = '<Border Grid.Column="2" Background="#E8F1FA" CornerRadius="10" Padding="10,2" VerticalAlignment="Center"><TextBlock Text="' + (Esc $app.Tag) + '" FontSize="12" Foreground="#0B5CA5"/></Border>'
    }
    New-Xaml @"
<Border $ns $tip Background="White" BorderBrush="#E1E1E1" BorderThickness="1" CornerRadius="6" Padding="14,8" Margin="0,0,0,6">
  <CheckBox x:Name="Chk" HorizontalContentAlignment="Stretch" VerticalContentAlignment="Center">
    <Grid Margin="8,0,0,0">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/>
      </Grid.ColumnDefinitions>
      $(Get-BadgeXaml $app)
      <StackPanel Grid.Column="1" VerticalAlignment="Center">
        <TextBlock Text="$(Esc $app.Name)" FontSize="14" FontWeight="SemiBold" Foreground="#1B1B1B"/>
        <TextBlock Text="$site" FontSize="12" Foreground="#5C5C5C"/>
        <TextBlock Text="$detail" FontSize="12" Foreground="#5C5C5C"/>
      </StackPanel>
      $tag
    </Grid>
  </CheckBox>
</Border>
"@
}

function New-ProgressRow($app) {
    New-Xaml @"
<Border $ns Background="White" BorderBrush="#E1E1E1" BorderThickness="1" CornerRadius="6" Padding="14,8" Margin="0,0,0,6">
  <Grid>
    <Grid.ColumnDefinitions>
      <ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/>
    </Grid.ColumnDefinitions>
    $(Get-BadgeXaml $app)
    <StackPanel Grid.Column="1" VerticalAlignment="Center">
      <TextBlock Text="$(Esc $app.Name)" FontSize="14" FontWeight="SemiBold" Foreground="#1B1B1B"/>
      <TextBlock x:Name="Sub" Text="Waiting" FontSize="12" Foreground="#5C5C5C" TextWrapping="Wrap"/>
      <ProgressBar x:Name="Bar" Height="6" Minimum="0" Maximum="100" Margin="0,6,0,0" Visibility="Collapsed" Foreground="#0F6CBD" Background="#E1E1E1" BorderThickness="0"/>
    </StackPanel>
    <TextBlock x:Name="Status" Grid.Column="2" Text="Queued" FontSize="13" FontWeight="SemiBold" Foreground="#5C5C5C" VerticalAlignment="Center" Margin="12,0,0,0"/>
  </Grid>
</Border>
"@
}

function Get-EdgeUninstallEntry {
    $roots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($root in $roots) {
        $entries = @(Get-ItemProperty -Path $root -ErrorAction SilentlyContinue | Where-Object {
            $_.DisplayName -eq 'Microsoft Edge' -and $_.NoRemove -eq 0 -and $_.UninstallString
        })
        foreach ($entry in $entries) {
            $uninstall = [string]$entry.UninstallString
            if ($uninstall -match '^\s*"([^"]+)"\s*(.*)$') {
                $exe = $Matches[1]
                $arguments = $Matches[2]
            } elseif ($uninstall -match '^\s*(\S+)\s+(.*)$') {
                $exe = $Matches[1]
                $arguments = $Matches[2]
            } else { continue }
            if ($exe -match '\\Microsoft\\Edge\\Application\\[^\\]+\\Installer\\setup\.exe$' -and
                $arguments -match '(?i)(^|\s)--uninstall(\s|$)' -and (Test-Path -LiteralPath $exe)) {
                return @{ FilePath=$exe; Arguments=$arguments }
            }
        }
    }
    return $null
}

function Get-DebloatChoices {
    $targets = @(
        @{ Name='Microsoft Edge'; Kind='edge'; Description='Uninstall is available only in supported regions (including the EEA) and Windows versions; removal may affect all users.' }
        @{ Name='Microsoft Teams (personal)'; Kind='appx'; Packages=@('MSTeams','MicrosoftTeams') }
        @{ Name='Clipchamp'; Kind='appx'; Packages=@('Clipchamp.Clipchamp') }
        @{ Name='Xbox app'; Kind='appx'; Packages=@('Microsoft.GamingApp') }
        @{ Name='Microsoft Solitaire Collection'; Kind='appx'; Packages=@('Microsoft.MicrosoftSolitaireCollection') }
        @{ Name='Microsoft Copilot'; Kind='appx'; Packages=@('Microsoft.Copilot') }
        @{ Name='Microsoft 365 app'; Kind='appx'; Packages=@('Microsoft.MicrosoftOfficeHub') }
        @{ Name='OneDrive'; Kind='onedrive'; Description='Removing the sync app stops future syncing; it does not intentionally delete cloud files.' }
        @{ Name='Tips'; Kind='appx'; Packages=@('Microsoft.Getstarted') }
        @{ Name='Feedback Hub'; Kind='appx'; Packages=@('Microsoft.WindowsFeedbackHub') }
        @{ Name='Phone Link'; Kind='appx'; Packages=@('Microsoft.YourPhone') }
        @{ Name='Microsoft News'; Kind='appx'; Packages=@('Microsoft.BingNews') }
        @{ Name='Microsoft Bing Weather'; Kind='appx'; Packages=@('Microsoft.BingWeather') }
    )
    $choices = @()
    foreach ($target in $targets) {
        $choice = @{ Target=$target; Packages=@(); FilePath=$null; Arguments=$null; Available=$false; Detail='Not installed for this user' }
        if ($target.Kind -eq 'appx') {
            foreach ($packageName in $target.Packages) {
                $choice.Packages += @(Get-AppxPackage -Name $packageName -ErrorAction Stop | Where-Object { $_.Name -eq $packageName })
            }
            if ($choice.Packages.Count -gt 0) {
                $choice.Available = $true
                $choice.Detail = 'Installed for this user'
            }
        } elseif ($target.Kind -eq 'edge') {
            $edge = Get-EdgeUninstallEntry
            if ($edge) {
                $choice.Available = $true
                $choice.FilePath = $edge.FilePath
                $choice.Arguments = $edge.Arguments
                $choice.Detail = 'Windows exposes a supported uninstall option'
            } else {
                $choice.Detail = 'Unavailable: Windows does not expose a supported uninstall option on this PC. Edge uninstall is limited to supported regions (including the EEA) and Windows versions.'
            }
        } else {
            $installed = @($script:InstalledNames | Where-Object { $_ -eq 'Microsoft OneDrive' })
            $setups = @(
                (Join-Path $env:SystemRoot 'SysWOW64\OneDriveSetup.exe'),
                (Join-Path $env:SystemRoot 'System32\OneDriveSetup.exe')
            )
            $setup = $setups | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
            if ($installed.Count -gt 0 -and $setup) {
                $choice.Available = $true
                $choice.FilePath = $setup
                $choice.Detail = $target.Description
            }
        }
        $choices += $choice
    }
    return $choices
}

function Invoke-DebloatChoice($choice) {
    if ($choice.Target.Kind -eq 'appx') {
        $removed = 0
        foreach ($package in $choice.Packages) {
            $current = @(Get-AppxPackage -Name $package.Name -ErrorAction Stop |
                Where-Object { $_.PackageFullName -eq $package.PackageFullName })
            foreach ($installedPackage in $current) {
                Remove-AppxPackage -Package $installedPackage.PackageFullName -ErrorAction Stop
                $removed++
                $script:DebloatChanged = $true
            }
        }
        if ($removed -eq 0) { return 'Already removed' }
        return 'Removed for this user'
    }
    if ($choice.Target.Kind -eq 'edge') {
        $edge = Get-EdgeUninstallEntry
        if (-not $edge) { return 'Skipped: Windows does not expose the supported uninstall option' }
        $process = Start-Process -FilePath $edge.FilePath -ArgumentList $edge.Arguments -PassThru
    } else {
        if (-not (Test-Path -LiteralPath $choice.FilePath)) { return 'Skipped: uninstaller is no longer available' }
        $process = Start-Process -FilePath $choice.FilePath -ArgumentList '/uninstall' -PassThru
    }
    Wait-ProcessUI $process
    if ($process.ExitCode -ne 0) { throw "Uninstaller exited with code $($process.ExitCode)" }
    $script:DebloatChanged = $true
    return 'Uninstalled'
}

function Show-DebloatDialog {
    $selectionBefore = @(Get-Selected | ForEach-Object { $_.Id })
    $choices = @(Get-DebloatChoices)
    $dialog = New-Xaml @"
<Window $ns Title="Debloat Windows" Width="560" Height="620" MinWidth="480" MinHeight="420"
        WindowStartupLocation="CenterOwner" Background="#F3F3F3" FontFamily="Segoe UI" ShowInTaskbar="False">
  <Grid Margin="20">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <StackPanel Grid.Row="0" Margin="0,0,0,12">
      <TextBlock Text="Choose apps to remove" FontSize="18" FontWeight="SemiBold" Foreground="#1B1B1B"/>
      <TextBlock Text="App package removals affect the current user. Edge uses Windows' standard uninstaller and may affect all users. Provisioned apps are not removed."
                 FontSize="12" Foreground="#5C5C5C" TextWrapping="Wrap" Margin="0,4,0,0"/>
    </StackPanel>
    <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto">
      <StackPanel x:Name="TargetList"/>
    </ScrollViewer>
    <DockPanel Grid.Row="2" Margin="0,12,0,0" LastChildFill="False">
      <TextBlock x:Name="DebloatStatus" VerticalAlignment="Center" FontSize="12" Foreground="#5C5C5C" TextWrapping="Wrap"/>
      <StackPanel DockPanel.Dock="Right" Orientation="Horizontal">
        <Button x:Name="DebloatCancel" Content="Cancel" MinWidth="84" Height="36" Margin="0,0,8,0" Padding="12,0" Background="White" BorderBrush="#BDBDBD"/>
        <Button x:Name="DebloatConfirm" Content="Remove selected" MinWidth="120" Height="36" Padding="12,0" Background="#0F6CBD" Foreground="White" FontWeight="SemiBold" BorderThickness="0"/>
      </StackPanel>
    </DockPanel>
  </Grid>
</Window>
"@
    Set-RoundedButtonStyle $dialog
    Set-SlimScrollbarStyle $dialog
    $dialog.Owner = $window
    $targetList = $dialog.FindName('TargetList')
    $status = $dialog.FindName('DebloatStatus')
    $removeButton = $dialog.FindName('DebloatConfirm')
    $cancelButton = $dialog.FindName('DebloatCancel')
    $rows = @()
    $script:DebloatChanged = $false
    foreach ($choice in $choices) {
        $name = Esc $choice.Target.Name
        $detail = Esc $choice.Detail
        $row = New-Xaml @"
<Border $ns Background="White" BorderBrush="#E1E1E1" BorderThickness="1" CornerRadius="5" Padding="10,7" Margin="0,0,0,5">
  <StackPanel>
    <CheckBox x:Name="TargetCheck" Content="$name" IsEnabled="$($choice.Available.ToString().ToLowerInvariant())"
              FontSize="13" FontWeight="SemiBold" Foreground="#1B1B1B"/>
    <TextBlock Text="$detail" FontSize="11" Foreground="#5C5C5C" TextWrapping="Wrap" Margin="20,2,0,0"/>
  </StackPanel>
</Border>
"@
        $checkbox = $row.FindName('TargetCheck')
        $null = $targetList.Children.Add($row)
        $rows += @{ Choice=$choice; Check=$checkbox }
    }
    $cancelButton.Add_Click(({ $dialog.Close() }).GetNewClosure())
    $removeHandler = {
        $selected = @($rows | Where-Object { $_.Check.IsChecked -and $_.Choice.Available })
        if ($selected.Count -eq 0) { $status.Text = 'Select at least one available app to remove.'; return }
        $names = @($selected | ForEach-Object { $_.Choice.Target.Name }) -join "`n"
        $warning = "Proceed with removing these items?`n`n$names`n`nApp package removals affect the current user. Edge uses Windows' standard uninstaller and may affect all users. Removing OneDrive stops syncing but does not intentionally delete cloud files."
        $answer = [Windows.MessageBox]::Show($warning, 'Confirm removal', 'YesNo', 'Warning')
        if ($answer -ne 'Yes') { return }
        $removeButton.IsEnabled = $false
        $cancelButton.IsEnabled = $false
        $failures = 0
        foreach ($item in $selected) {
            $status.Text = "Removing $($item.Choice.Target.Name)..."
            Update-UI
            try {
                $result = Invoke-DebloatChoice $item.Choice
                Write-Log "Debloat $($item.Choice.Target.Name): $result"
                $status.Text = "$($item.Choice.Target.Name): $result"
                if ($result -like 'Skipped:*') { $failures++ }
            } catch {
                $message = Get-Err $_
                Write-Log "Debloat $($item.Choice.Target.Name) failed: $message"
                $status.Text = "$($item.Choice.Target.Name) failed: $message"
                $failures++
            }
            Update-UI
        }
        $removeButton.IsEnabled = $true
        $cancelButton.IsEnabled = $true
        if ($failures -eq 0) { $status.Text = 'Finished. Close this dialog to refresh the app list.' }
        else { $status.Text += " $failures item(s) were skipped or failed; see the log for details." }
    }.GetNewClosure()
    $removeButton.Add_Click($removeHandler)
    [void]$dialog.ShowDialog()
    if ($script:DebloatChanged) {
        Show-Picker
        foreach ($id in $selectionBefore) {
            if ($Checks.ContainsKey($id)) { $Checks[$id].IsChecked = $true }
        }
    }
}


# ---- 5.5  Selection and footer -------------------------------------------
# Apps the user ticked. Locked (already installed) apps are never in $Checks, so they can never be selected.
function Get-Selected {
    @($Apps | Where-Object { $Checks.ContainsKey($_.Id) -and $Checks[$_.Id].IsChecked })
}

function Update-Footer {
    $sel = @(Get-Selected)
    if ($sel.Count -eq 0) {
        $t = 'Nothing selected'
    } else {
        $t = "$($sel.Count) selected"
        if ($sel | Where-Object { $_.Pre -eq 'BravePolicies' }) { $t += " $Dot Brave policies are applied before install" }
        $proj = @($sel | Where-Object { $_.Kind -eq 'irm' })
        if ($proj.Count -gt 0) { $t += " $Dot $($proj[0].Name)" }
    }
    if ($script:InstalledCount -gt 0) { $t += " $Dot $($script:InstalledCount) already installed" }
    $FooterText.Text = $t
    $BtnPrimary.IsEnabled = ($sel.Count -gt 0)
}


# ---- 5.6  Row status helpers (used while installing) ---------------------
# ------------------------------------------------------------------ per-app pipeline
function Set-Row($id, $status, $color, $sub) {
    $r = $script:Rows[$id]
    if ($null -ne $status) { $r.Status.Text = $status; $r.Status.Foreground = Brush $color }
    if ($null -ne $sub)    { $r.Sub.Text = $sub }
    Update-UI
}
function Set-Bar($id, $pct) {
    $b = $script:Rows[$id].Bar
    if ($null -eq $pct) { $b.Visibility = 'Collapsed' } else { $b.Visibility = 'Visible'; $b.Value = $pct }
}





# ============================================================================
# 6. INSTALL ENGINE
#    The per-app pipeline: download -> verify signature -> install.
#    The "Project" (irm) entry has its own shorter path.
# ============================================================================
 

# ---- 6.1  Download -------------------------------------------------------
function Save-Download($app, $dest) {
    $client = New-Object System.Net.Http.HttpClient
    $client.Timeout = [TimeSpan]::FromMinutes(30)
    $client.DefaultRequestHeaders.UserAgent.ParseAdd('Mozilla/5.0 (Windows NT 10.0; Win64; x64) PCSetter/1.0')
    try {
        $urls = @($app.Url)
        if ($app.Urls) { $urls = @($app.Urls) }
        $resp = $null
        foreach ($u in $urls) {
            try {
                $resp = $client.GetAsync($u, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).Result
                $null = $resp.EnsureSuccessStatusCode()
                break
            } catch {
                Write-Log "$($app.Name): $u failed - $(Get-Err $_)"
                $resp = $null
                if ($u -eq $urls[-1]) { throw }
            }
        }
        $final = $resp.RequestMessage.RequestUri
        if ($final.Scheme -ne 'https') { throw "Refusing non-HTTPS download ($($final.AbsoluteUri))" }
        $allowed = $false
        foreach ($h in $app.Hosts) {
            if ($final.Host -eq $h -or $final.Host.EndsWith('.' + $h)) { $allowed = $true }
        }
        if (-not $allowed) { throw "Download redirected to unexpected host '$($final.Host)'" }
        Write-Log "$($app.Name): downloading $($final.AbsoluteUri)"

        $total = $resp.Content.Headers.ContentLength
        $in  = $resp.Content.ReadAsStreamAsync().Result
        $out = [IO.File]::Create($dest)
        try {
            $buf = New-Object byte[] 81920
            $done = 0L
            $clock = [Diagnostics.Stopwatch]::StartNew()
            while (($n = $in.Read($buf, 0, $buf.Length)) -gt 0) {
                $out.Write($buf, 0, $n)
                $done += $n
                if ($clock.ElapsedMilliseconds -gt 100) {
                    $clock.Restart()
                    if ($total) { Set-Bar $app.Id ([int](100 * $done / $total)) }
                    Update-UI
                    if ($script:Cancel) { throw 'Cancelled' }
                }
            }
        } finally { $out.Dispose(); $in.Dispose() }
    } finally { $client.Dispose() }
}


# ---- 6.2  Wait for a process while keeping the window alive --------------
function Wait-ProcessUI($p) {
    while (-not $p.HasExited) { Start-Sleep -Milliseconds 200; Update-UI }
    $p.WaitForExit()
}


# ---- 6.3  Project entry (irm | iex in its own window) --------------------
# Kind 'irm': no installer file and no signature. The address is checked (https + allowed host), then a hidden
# PowerShell wrapper runs "irm <url> | iex". MAS opens its own visible interactive terminal. The installer
# waits for the wrapper to finish before it moves on (keep this entry first in $Apps).
function Start-ProjectScript($app) {
    $id = $app.Id
    if ($app.Url -like '*YOUR-USER*') { throw 'Set $ProjectUrl at the top of the script first' }
    Set-Row $id 'Checking' '#0B5CA5' 'Checking the script address'
    $uri = [Uri]$app.Url
    if ($uri.Scheme -ne 'https') { throw "Refusing non-HTTPS address ($($uri.AbsoluteUri))" }
    $allowed = $false
    foreach ($h in $app.Hosts) {
        if ($uri.Host -eq $h -or $uri.Host.EndsWith('.' + $h)) { $allowed = $true }
    }
    if (-not $allowed) { throw "Script address is on an unexpected host '$($uri.Host)'" }
    Write-Log "$($app.Name): script address $($uri.AbsoluteUri)"

    if ($VerifyOnly) {
        Set-Row $id 'Verified' '#0E6B0E' "Address OK $Dot $($uri.Host) (not run)"
        $script:Results[$id] = 'done'
        return
    }

    Set-Row $id 'Running' '#0B5CA5' 'Running in the MAS terminal - the other apps start when it finishes'
    $errorFile = Join-Path $WorkDir 'mas-error.txt'
    $quotedUrl = $uri.AbsoluteUri.Replace("'", "''")
    $quotedErrorFile = $errorFile.Replace("'", "''")
    $cmd = '$Host.UI.RawUI.WindowTitle = ''Microsoft Activation Scripts (MAS) - PCSetter''; [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; try { irm ' +
        "'" + $quotedUrl + "'" + ' | iex } catch { Set-Content -LiteralPath ' + "'" + $quotedErrorFile + "'" +
        ' -Value $_.Exception.Message; exit 1 }; exit 0'
    $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd))
    $p = Start-Process -FilePath powershell.exe -WindowStyle Hidden -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $encodedCommand) -PassThru
    Wait-ProcessUI $p
    $code = $p.ExitCode
    Write-Log "$($app.Name): PowerShell window closed (exit code $code)"
    if ($code -ne 0) {
        $detail = if (Test-Path -LiteralPath $errorFile) { Get-Content -LiteralPath $errorFile -Raw } else { "exit code $code" }
        throw "The script failed: $detail"
    }
    Set-Row $id 'Done' '#0E6B0E' 'Script finished'
    $script:Results[$id] = 'done'
}


# ---- 6.4  Install one app ------------------------------------------------
function Install-App($app) {
    $id   = $app.Id
    $file = Join-Path $WorkDir ([string]$app.File)   # the irm entry has no file
    try {
        if ($app.Kind -eq 'irm') { Start-ProjectScript $app; return }

        Set-Row $id 'Downloading' '#0B5CA5' "Downloading from $($app.Site)"
        Set-Bar $id 0
        Save-Download $app $file
        Set-Bar $id $null

        Set-Row $id 'Verifying' '#0B5CA5' 'Checking the digital signature'
        $v = Test-AppSignature $file $app.Signer
        Write-Log "$($app.Name): signer='$($v.Signer)' thumbprint=$($v.Thumb) ok=$($v.Ok) $($v.Why)"
        if (-not $v.Ok) {
            Remove-Item $file -Force -ErrorAction SilentlyContinue
            Set-Row $id 'Skipped' '#B42318' $v.Why
            $script:Results[$id] = 'skipped'
            return
        }
        if ($VerifyOnly) {
            Set-Row $id 'Verified' '#0E6B0E' "Signed by $($v.Signer) $Dot thumbprint $($v.Thumb) (not installed)"
            $script:Results[$id] = 'done'
            return
        }

        $note = 'Signature verified'
        if ($app.Pre -eq 'BravePolicies') {
            $count = Set-BravePolicies
            $note += " $Dot $count policies applied"
        }

        if ($app.Interactive) { Set-Row $id 'Installing' '#0B5CA5' 'The publisher installer is open - finish it in its own window' }
        else                  { Set-Row $id 'Installing' '#0B5CA5' 'Running the installer' }

        $code = 0
        if ($app.Kind -eq 'msi') {
            $p = Start-Process -FilePath msiexec.exe -ArgumentList @('/i', "`"$file`"", '/qn', '/norestart') -PassThru
            Wait-ProcessUI $p
            $code = $p.ExitCode
        }
        elseif ($app.Unelevated) {
            # Some installers (Spotify) refuse to run elevated: start with a standard-user token and wait for the app to appear.
            Start-Process -FilePath runas.exe -ArgumentList @('/trustlevel:0x20000', "`"$file`"") -WindowStyle Hidden | Out-Null
            $clock = [Diagnostics.Stopwatch]::StartNew()
            while (-not (Test-Path $app.Detect) -and $clock.Elapsed.TotalSeconds -lt 180) { Start-Sleep -Milliseconds 500; Update-UI }
            if (-not (Test-Path $app.Detect)) { throw 'The installer did not finish within 3 minutes' }
            $clock.Restart()
            while ($clock.Elapsed.TotalSeconds -lt 3) { Start-Sleep -Milliseconds 200; Update-UI }
        }
        else {
            $sp = @{ FilePath = $file; PassThru = $true }
            if ($app.Args) { $sp.ArgumentList = $app.Args }
            $p = Start-Process @sp
            Wait-ProcessUI $p
            $code = $p.ExitCode
        }

        if ($code -notin 0, 3010, 1641) { throw "Installer exited with code $code" }
        Write-Log "$($app.Name): installed (exit code $code)"
        Set-Row $id 'Installed' '#0E6B0E' $note
        $script:Results[$id] = 'done'
    }
    catch {
        $msg = Get-Err $_
        Write-Log "$($app.Name): FAILED - $msg"
        Set-Bar $id $null
        if ($msg -eq 'Cancelled') { Set-Row $id 'Cancelled' '#5C5C5C' 'Cancelled'; $script:Results[$id] = 'cancelled' }
        else                      { Set-Row $id 'Failed' '#B42318' $msg;           $script:Results[$id] = 'failed' }
    }
}





# ============================================================================
# 7. SCREENS
#    The two screens of the window: the app picker and the install-progress view.
# ============================================================================
 

# ---- 7.1  Picker screen --------------------------------------------------
# Builds the list of apps. Runs at start-up and again from the "Back to installer" button, so apps that were
# installed in the meantime show up locked and the rest can be picked again.
function Add-DebloatSection {
    $enabled = if ($VerifyOnly) { 'False' } else { 'True' }
    $section = New-Xaml @"
<Border $ns Background="White" BorderBrush="#E1E1E1" BorderThickness="1" CornerRadius="6" Padding="14,10" Margin="0,6,0,8">
  <Grid>
    <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
    <StackPanel VerticalAlignment="Center">
      <TextBlock Text="Debloat Windows" FontSize="14" FontWeight="SemiBold" Foreground="#1B1B1B"/>
      <TextBlock Text="Review and optionally remove built-in apps" FontSize="12" Foreground="#5C5C5C" Margin="0,3,12,0"/>
    </StackPanel>
    <Button x:Name="DebloatButton" Grid.Column="1" Content="Debloat" IsEnabled="$enabled" MinWidth="88" Height="36" Padding="12,0" Background="White" BorderBrush="#BDBDBD"/>
  </Grid>
</Border>
"@
    $debloatButton = $section.FindName('DebloatButton')
    $debloatButton.Add_Click({
        try { Show-DebloatDialog }
        catch {
            $message = Get-Err $_
            Write-Log "Debloat UI error: $message"
            [void][Windows.MessageBox]::Show("Could not open Debloat:`n`n$message", 'PCSetter', 'OK', 'Error')
        }
    })
    $null = $List.Children.Add($section)
}

function Show-Picker {
    $script:Phase  = 'pick'
    $script:Cancel = $false
    $List.Children.Clear()
    $Checks.Clear()
    $script:InstalledNames = Get-InstalledNames
    $script:InstalledCount = 0

    $Heading.Text = 'Choose your apps'
    $BtnPrimary.Content = 'Install'
    $BtnSecondary.Content = 'Clear'
    $BtnSecondary.IsEnabled = $true

    $cat = $null
    $debloatSectionAdded = $false
    foreach ($app in $Apps) {
        if ($app.Category -ne $cat) {
            if ($cat -eq 'Windows' -and -not $debloatSectionAdded) {
                Add-DebloatSection
                $debloatSectionAdded = $true
            }
            $cat = $app.Category
            $null = $List.Children.Add((New-Xaml ('<TextBlock {0} Text="{1}" FontSize="12" FontWeight="SemiBold" Foreground="#5C5C5C" Margin="0,10,0,6"/>' -f $ns, (Esc $cat.ToUpper()))))
        }
        # Verify-only mode installs nothing, so there is nothing to protect from duplicates: no locking there.
        $found = $null
        if (-not $VerifyOnly) { $found = Test-AppInstalled $app }
        $row = New-PickRow $app ([bool]$found)
        $chk = $row.FindName('Chk')
        if ($found) {
            $chk.IsChecked = $true
            $chk.Template = $window.FindResource('LockedCheck')
            $chk.IsHitTestVisible = $false
            $chk.Focusable = $false
            $script:InstalledCount++
            Write-Log "$($app.Name): already installed ($found)"
        } else {
            $chk.Add_Checked({ Update-Footer })
            $chk.Add_Unchecked({ Update-Footer })
            $Checks[$app.Id] = $chk
        }
        $null = $List.Children.Add($row)
    }
    if ($cat -eq 'Windows' -and -not $debloatSectionAdded) { Add-DebloatSection }

    $Subheading.Text = 'Each installer is downloaded from the publisher official site. Its digital signature is checked before it runs.'
    if ($script:InstalledCount -gt 0) { $Subheading.Text += ' Apps already installed on this PC are locked.' }
    if ($VerifyOnly) { $Subheading.Text += ' (Verify-only mode: nothing will be installed.)' }
    Update-Footer
}


# ---- 7.2  Install-progress screen ----------------------------------------
function Start-Run($selected) {
    $script:Phase = 'run'
    $script:Cancel = $false
    $script:Rows = @{}
    $script:Results = @{}

    $plural = ''
    if ($selected.Count -ne 1) { $plural = 's' }
    $Heading.Text = "Installing $($selected.Count) app$plural"
    if ($VerifyOnly) { $Subheading.Text = 'Verify-only mode: installers are downloaded and checked, nothing is installed.' }
    else             { $Subheading.Text = 'Please keep this window open until it finishes.' }

    $List.Children.Clear()
    foreach ($app in $selected) {
        $r = New-ProgressRow $app
        $script:Rows[$app.Id] = @{ Sub = $r.FindName('Sub'); Bar = $r.FindName('Bar'); Status = $r.FindName('Status') }
        $null = $List.Children.Add($r)
    }
    $BtnPrimary.Content = 'Close'
    $BtnPrimary.IsEnabled = $false
    $BtnSecondary.Content = 'Cancel remaining'
    $BtnSecondary.IsEnabled = $true
    $FooterText.Text = "Log: $LogPath"
    Update-UI

    New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
    foreach ($app in $selected) {
        if ($script:Cancel) {
            Set-Row $app.Id 'Cancelled' '#5C5C5C' 'Not started'
            $script:Results[$app.Id] = 'cancelled'
            continue
        }
        Install-App $app
    }
    Remove-Item $WorkDir -Recurse -Force -ErrorAction SilentlyContinue

    $ok   = @($script:Results.Values | Where-Object { $_ -eq 'done' }).Count
    $rest = $selected.Count - $ok
    $Heading.Text = 'Finished'
    $Subheading.Text = "$ok done $Dot $rest skipped, failed or cancelled. Details are in the log."
    $script:Phase = 'done'
    $BtnPrimary.IsEnabled = $true
    $BtnSecondary.Content = 'Back to installer'     # return to the list without restarting the script
    $BtnSecondary.IsEnabled = $true
}





# ============================================================================
# 8. ENTRY POINT
#    Shows the picker, connects the buttons and opens the window.
# ============================================================================

Show-Picker

$BtnPrimary.Add_Click({
    try {
        if ($script:Phase -eq 'done') { $window.Close(); return }
        if ($script:Phase -ne 'pick') { return }
        $selected = @(Get-Selected)
        if ($selected.Count -gt 0) { Start-Run $selected }
    } catch {
        $m = Get-Err $_
        Write-Log "UI error: $m"
        [void][Windows.MessageBox]::Show("Something went wrong:`n`n$m", 'PCSetter', 'OK', 'Error')
        $script:Phase = 'done'
        $BtnPrimary.Content = 'Close'
        $BtnPrimary.IsEnabled = $true
        $BtnSecondary.Content = 'Back to installer'
        $BtnSecondary.IsEnabled = $true
    }
})
$BtnSecondary.Add_Click({
    if ($script:Phase -eq 'pick') { foreach ($c in $Checks.Values) { $c.IsChecked = $false } }
    elseif ($script:Phase -eq 'run') { $script:Cancel = $true; $BtnSecondary.IsEnabled = $false }
    elseif ($script:Phase -eq 'done') {
        try { Show-Picker }
        catch {
            $m = Get-Err $_
            Write-Log "UI error: $m"
            [void][Windows.MessageBox]::Show("Could not go back to the installer:`n`n$m", 'PCSetter', 'OK', 'Error')
        }
    }
})
$window.Add_Closing({ if ($script:Phase -eq 'run') { $args[1].Cancel = $true } })

try { [void]$window.ShowDialog() }
finally { Remove-Item $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
