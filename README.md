# PCSetter

PCSetter is a Windows app installer that runs without you needing to download anything.</br>Select apps, and it downloads installers from their configured publisher sites, verifies their signatures, and runs them.

<p align="center">
  <img src="PCSetter.png" alt="PCSetter app window">
</p>

## How to Run it

Open PowerShell ***as administrator*** and run the script from GitHub using the following command:

```powershell
irm 'https://raw.githubusercontent.com/Pereira3/PCSetter/main/PCSetter.ps1' | iex
```


## Use

1. Select the apps to install and press **Install**.
2. Follow progress in PCSetter. Use **Cancel remaining** to stop the queue; an installer already running is not forcibly stopped.
3. When finished, choose **Close** or **Back to installer**.

Microsoft Activation Scripts (MAS) is a third-party project from massgrave.dev that provides scripts for Windows and Office activation. PCSetter runs its hosted script first in an interactive terminal. Use it only in accordance with applicable licensing terms.

## Currently available

| App | Notes |
|---|---|
| Microsoft Activation Scripts (MAS) | Runs first. Its live script is not signature-verified; see the security note below. |
| Brave | Silent install; PCSetter applies its configured Brave policies first. |
| Spotify | Runs as a standard user. |
| Steam | Tries two configured download mirrors. |
| Epic Games Launcher | Silent MSI install. |
| League of Legends | Publisher installer is interactive. |

### Brave policies applied by PCSetter

Before installing Brave, PCSetter writes machine-wide policies that disable:

- Brave Rewards, News, and Talk
- Sync
- Wallet and VPN
- AI Chat (Leo)
- Tor windows

These policies apply to all users on the PC. Brave may show a “managed by your organization” notice. To undo them, remove `HKLM:\SOFTWARE\Policies\BraveSoftware\Brave`.

## Download checks and limitations

For downloaded installer files, PCSetter requires HTTPS, an allowed publisher host (including after redirects), a valid Authenticode signature, and the expected signer name. If a check fails, the installer is not run.

MAS is different: PCSetter checks its HTTPS address and allowed host, then runs the live script with administrator rights. It does not download and verify a signed installer for MAS. Only run it if you trust the source.

## Configuration and logs

The latest run is logged to `%TEMP%\pcsetter.log`. When you elevate using the same Windows account, this is your user temp folder and the log is normally readable after the run. If you enter credentials for a different administrator account, `%TEMP%` may point to that account's folder instead. Downloaded files are kept in a temporary `PCSetter-*` folder during a run and removed afterward.