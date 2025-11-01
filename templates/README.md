# __PROJECT__

One-liner to auto-install & run (& dev) a `fdevc runnable project` for __PROJECT__ powered by [fdevc](https://github.com/philogicae/fast_dev_container)

[![Curl](https://img.shields.io/badge/curl-required-orange)](https://curl.se/)
[![Git](https://img.shields.io/badge/git-required-orange)](https://git-scm.com/)
[![Docker](https://img.shields.io/badge/docker-required-orange)](https://www.docker.com/get-started/)
[![Python](https://img.shields.io/badge/python-3.10%2B-blue)](https://www.python.org/downloads/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/__USER__/__PROJECT__)

## Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/__USER__/__PROJECT__/main/install_and_run | bash
```

<div style="display:flex;gap:20px;align-items:stretch;margin:20px 0;flex-wrap:wrap"><div style="flex:1 1 100%;display:flex;flex-direction:column"><div style="background:linear-gradient(135deg,#1e293b 0%,#0f172a 100%);border-radius:12px;padding:24px;box-shadow:0 10px 30px rgba(0,0,0,0.5);font-family:'Segoe UI',Tahoma,Geneva,Verdana,sans-serif;flex:1;display:flex;flex-direction:column"><div style="color:#f1f5f9;font-size:20px;font-weight:600;margin-bottom:16px;text-shadow:0 2px 4px rgba(0,0,0,0.5)">📁 __PROJECT__/</div><div style="background:rgba(30,41,59,0.5);border-radius:8px;padding:16px;backdrop-filter:blur(10px);border:1px solid rgba(148,163,184,0.2);flex:1"><div style="color:#f1f5f9;font-family:'Consolas','Monaco',monospace;line-height:1.2"><div style="display:flex;justify-content:space-between"><span style="color:#f1f5f9">├── <a href="./install_and_run" style="color:#06b6d4;text-decoration:none;font-weight:500;hover:underline">install_and_run</a></span><span style="color:#94a3b8;font-size:12px;white-space:nowrap"># Auto-install script</span></div><div style="display:flex;justify-content:space-between"><span style="color:#f1f5f9">├── <a href="./launch.sh" style="color:#06b6d4;text-decoration:none;font-weight:500;hover:underline">launch.sh</a></span><span style="color:#94a3b8;font-size:12px;white-space:nowrap"># Container launcher</span></div><div style="display:flex;justify-content:space-between"><span style="color:#f1f5f9">├── <span style="color:#ef4444;font-weight:500">project/</span></span><span style="color:#94a3b8;font-size:12px;white-space:nowrap"># Git project mount</span></div><div style="display:flex;justify-content:space-between"><span style="color:#f1f5f9">└── <a href="./fdevc_setup" style="color:#10b981;text-decoration:none;font-weight:500;hover:underline">fdevc_setup/</a></span><span style="color:#94a3b8;font-size:12px;white-space:nowrap"># Setup scripts mount</span></div><div style="display:flex;justify-content:space-between"><span style="color:#f1f5f9">&emsp;&emsp;&emsp;&emsp;└── <a href="./fdevc_setup/runnable.sh" style="color:#10b981;text-decoration:none;font-weight:500;hover:underline">runnable.sh</a></span><span style="color:#94a3b8;font-size:12px;white-space:nowrap"># Main container script</span></div></div></div></div></div></div>

- **`install_and_run`** - Installation script that ensures `fdevc` is available, clones this repository, and runs `launch.sh`.
- **`launch.sh`** - Helper script to launch a container using `fdevc` with predefined settings. Edit the configuration variables at the top to customize ports, image, persistence, etc.
- **`fdevc_setup/runnable.sh`** - The main script that runs inside the container.
- **`project/`** - The mounted target folder for git cloned project

# TODO & REMOVE (for runnable project creators)

1. **Replace** all `__USER__` with your `GitHub username` in the project.
2. **Edit** `fdevc_setup/runnable.sh` to add your setup commands, install tools, or run applications.
3. **Edit** `launch.sh` to change container configuration (ports, image, persistence mode, etc.).
4. **Edit** `README.md` to match your project's needs, remove `TODO & REMOVE` section and add `Usage` section.
5. **Optional:** Run `fdevc custom` in the project to create a custom ./fdevc.Dockerfile for more advanced configurations.
6. **Optional:** Test locally `./launch.sh`.
7. **Push** to GitHub and share: `curl -fsSL https://raw.githubusercontent.com/__USER__/__PROJECT__/main/install_and_run | bash`