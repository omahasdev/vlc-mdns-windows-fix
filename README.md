# VLC 3 on Windows: Chromecast and network shares not found (mDNS fix)

On Windows PCs with more than one network adapter, VLC 3.0.x often does not
find a Chromecast. This repository explains the cause and fixes it with a
patched `libmicrodns_plugin.dll` that you build and install with one script.

## Symptoms

- **Playback > Renderer** shows "Scanning" for more than 20 s. This is the
  most common sign. Sometimes the Chromecast shows after up to 2 min,
  sometimes never.
- Chrome, Edge, and phones find the same Chromecast immediately.
- **Playlist > Local Network > mDNS Network Discovery** can also miss FTP,
  SMB, NFS, SFTP, and RTSP servers. They use the same discovery code.
- The PC has virtual or extra adapters: Hyper-V or WSL `vEthernet`,
  VirtualBox or VMware host-only, or VPN adapters.

## Cause

VLC 3.0.x discovers devices with [libmicrodns](https://github.com/videolabs/libmicrodns)
0.2.0. The library opens one socket for each interface, binds it to
`0.0.0.0:5353`, and joins `224.0.0.251` on that interface. It never sets
`IP_MULTICAST_IF`. Thus Windows sends every mDNS query out of its default
multicast interface. On the test PC, that was the WSL `vEthernet` adapter,
although Wi-Fi had the lowest metric. The query never got to the Chromecast.

VLC finds the device only when another device on the network asks for
Chromecasts. VLC then receives the multicast answer too. This is why the
wait is random.

Firewall rules, VPNs, and other programs that hold UDP 5353 (for example
TeamViewer) are not the cause.

## Fix

Requirements:

- Windows 10 or 11, x64
- VLC 3.0.x, 64-bit
- [Git for Windows](https://gitforwindows.org/)
- Internet for the first build (approximately 210 MB) and administrator rights

Do these steps:

1. Close VLC.
2. Run `install.cmd`.
3. Accept the UAC prompt. The window shows the result. The result is also in
   `install.log` in the work folder.
4. Open **Playback > Renderer**. The Chromecast must show in a few seconds.

Tested with VLC 3.0.24 x64 on Windows 11: before the fix, discovery took
16 s to more than 2 min. After the fix, the Chromecast showed in 3 s.

After each VLC update, run `install.cmd` again. The VLC installer puts the
original DLL back. To undo the fix, run `restore.cmd`.

The script builds the DLL if none exists for the installed VLC version, or
if the patches changed. It downloads the [llvm-mingw](https://github.com/mstorsjo/llvm-mingw)
toolchain (msvcrt), the VLC SDK, `microdns.c`, and the libmicrodns release that
the same VLC tag uses. It applies the VLC contrib patches, then the
[`patches/`](patches) of this repository:

- `libmicrodns-0.2.0-multicast-if.diff`: the fix
- `libmicrodns-0.2.0-upstream-665a8ce-txt-rdlength.patch`: the upstream fix
  for an out-of-bounds read in the TXT record parser. The stock VLC 3.0.24
  DLL does not have it.

Before it replaces the DLL, it compares the plugin ABI and saves the original.

`prepare.cmd` downloads these inputs only and needs no administrator rights.

### Folders

All downloads and output go into `.work` in this folder. To change this, set
these variables, or copy [`examples/vlc-mdns-fix.cmd`](examples/vlc-mdns-fix.cmd):

| Variable | Use | Default |
|---|---|---|
| `VLC_MDNS_FIX_WORK` | sources, DLLs, backups, logs | `.work` |
| `VLC_MDNS_FIX_SDK` | toolchain and VLC SDK | `VLC_MDNS_FIX_WORK` |
| `VLC_DIR` | VLC install folder | from the registry |
| `GIT_BASH` | `bash.exe` of Git for Windows | `%ProgramFiles%\Git\bin\bash.exe` |

## Diagnose

Close VLC, then run these tools with Python 3:

```bat
python tools\mcast_egress_probe.py
python tools\libmicrodns_query_test.py
python tools\libmicrodns_query_test.py --set-if
```

Your PC has this bug if these three results occur:

- `mcast_egress_probe.py` shows an adapter that is not on the Chromecast network.
- `libmicrodns_query_test.py` (the libmicrodns method) gets no answer.
- `libmicrodns_query_test.py --set-if` (with `IP_MULTICAST_IF`) gets an answer.

`--no-send --seconds 120` shows the answers that other devices cause.

## Workarounds without the patch

- Disable the virtual adapters that you do not need (`ncpa.cpl`).
  `wsl --shutdown` does not remove the WSL adapter.
- Cast from Chrome or Edge.

## Limits

- Only VLC 3.0.x, 64-bit. VLC 4 has a different plugin API.
- If a VLC 3.0 release changes the plugin ABI, the install stops. Delete
  `out\<version>` in the work folder and run `install.cmd` again.

## History

- 2016: VLC issue [#17477](https://code.videolan.org/videolan/vlc/-/issues/17477)
  and libmicrodns issue [#11](https://github.com/videolabs/libmicrodns/issues/11)
  found the missing `IP_MULTICAST_IF`.
- 2017: libmicrodns PR [#14](https://github.com/videolabs/libmicrodns/pull/14)
  added the join on each interface, but not the send interface.
- October 2026: libmicrodns master still does not set it. VLC 3.0.24 bundles
  libmicrodns 0.2.0.

## License

LGPL-2.1-or-later, the same license as libmicrodns and the VLC module.
