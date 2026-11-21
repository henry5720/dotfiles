#!/usr/bin/env python3
"""Windows 主機會部署什麼:用 --override-data 把 chezmoi.os 換成 windows／linux／android,
在 Linux 上驗 chezmoi 對這個 repo 會管哪些 target、config 樣板渲染出什麼(spec #254 的 Testing Decisions)。

Windows 白名單多一個檔案時:改 home/.chezmoiignore 的 Windows 段,再把 target 加進下面的 WINDOWS_TARGETS。
實機才驗得到的(PowerShell 讀不讀 profile、Terminal 讀不讀 settings.json)在 AGENTS.md「怎麼驗證」的實機清單。
"""
import base64
import json
import os
import tomllib
import re
import subprocess
import tempfile
import unittest
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parents[2]
CONFIG_TEMPLATE = ROOT / "home/.chezmoi.toml.tmpl"
# Windows 只部署這些 target;多一個、少一個都算錯。跟 home/.chezmoiignore 的 Windows 白名單對應
WINDOWS_TARGETS = {
    ".wslconfig",
    # 跟 Linux 同一份 ssh config(#307)
    ".ssh/config",
    ".config/starship.toml",
    "Documents/PowerShell/Profile.ps1",
    "Documents/WindowsPowerShell/Profile.ps1",
    "AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json",
    # mise 的清單:Windows 一定有 zoxide(PowerShell profile 的 z),所以每台都有
    ".config/mise/conf.d/dotfiles.toml",
    # PowerShell 版的 tools
    ".local/bin/tools.ps1",
}
# 勾了 opencode 才部署的設定(#318)。routes/personal 不放:它給 opencode-personal(ai-profile,Linux 的指令)用,
# 裡面還有 symlink(Windows 沒開 Developer Mode 建不了)
OPENCODE_TARGETS = {".config/opencode/opencode.json", ".config/opencode/oh-my-opencode-slim.json"}
# 勾了 claude 才部署的設定(#319)。plugins/claude-hud 不放:claude-hud 由 skillshare 的 plugin 裝,沒裝時那份設定沒人讀
CLAUDE_SETTINGS = ".claude/settings.json"
CLAUDE_COMMIT = "Co-Authored-By: Claude Code <noreply@anthropic.com>"
CHROME_PLUGIN = "chrome-devtools-mcp@claude-plugins-official"
# 只有 .ps1 腳本跑到 Windows(sh 腳本放行就會被 chezmoi 拿去執行而失敗)
WINDOWS_SCRIPTS = {
    ".chezmoiscripts/install-packages-windows.ps1",
    ".chezmoiscripts/install-mise.ps1",
    # 官方 install.ps1 裝的 coding agent(claude #316、codex #317,#334 併成一支照表跑);沒勾時渲染成空的,chezmoi 不跑,但仍是 managed
    ".chezmoiscripts/install-official.ps1",
    # agent-config(#321):官方 install.ps1 裝 skillshare、init;config 釘的兩段變了就 sync
    ".chezmoiscripts/install-agent-config.ps1",
    ".chezmoiscripts/sync-skillshare.ps1",
    # wakatime(#324):wakatime-cli 放官方位置,有勾的 agent 裝 plugin
    ".chezmoiscripts/install-wakatime.ps1",
    # MCP 的 API key(context7、graphify)設成使用者環境變數;沒填 key 時渲染成空的,但仍是 managed
    ".chezmoiscripts/set-mcp-env.ps1",
    ".chezmoiscripts/zz-env-skipped.ps1",
}
# 勾了 codex 才部署的設定(#320)。personal.config.toml、codex-gcp.config.toml 不放:給 ai-profile(只有 Linux)用
CODEX_TARGETS = {".codex/config.toml"}
CODEX_CONFIG = ROOT / "home/dot_codex/modify_private_config.toml.tmpl"
# Codex 自己寫過的 config.toml:codex 加的頂層 key(notify)、信任專案、TUI 計數器、hook,skillshare 寫的 MCP,
# 使用者在 developer_instructions 自己加的字(多行字串裡有像 table 的一行)
CODEX_EXISTING = (
    'model = "drifted"\napprovals_reviewer = "user"\n'
    'developer_instructions = """使用者自己的指引\n[features]\n照留。"""\n'
    'notify = [\n  "herdr",\n  "codex-notify",\n]\n\n'
    '[model_providers.codex-lb-gcp]\nname = "stale"\n\n'
    '[projects."C:\\\\Users\\\\h\\\\repo"]\ntrust_level = "trusted"\n\n'
    '[tui.model_availability_nux]\n"gpt-6.1-sol" = 3\n\n'
    '[features]\nhooks = true\n\n'
    '[[skills.config]]\npath = "C:/x/SKILL.md"\nenabled = false\n\n'
    '[mcp_servers.gh_grep]\nurl = "https://mcp.grep.app"\n\n'
    '[mcp_servers.context7]\nurl = "https://mcp.context7.com/mcp"\nbearer_token_env_var = "CONTEXT7_API_KEY"\n'
)
# skillshare 在 Windows 讀 %AppData%\skillshare\config.yaml(#321),勾了 agent-config 才部署
SKILLSHARE_CONFIG = "AppData/Roaming/skillshare/config.yaml"
# henry-desktop 上 skillshare 自己存的 config.yaml(LF,勾 claude、codex、opencode、agent-config)
SKILLSHARE_FIXTURE = ROOT / "script/tests/fixtures/windows-skillshare-config.yaml"
# WakaTime 的 API key(#324),兩個 plugin 都讀 %USERPROFILE%\.wakatime.cfg,勾了 wakatime 才部署
WAKATIME_CFG = ".wakatime.cfg"
# 只給 Windows 的 target(或它們的頂層目錄),Linux／Termux 不能部署
WINDOWS_ONLY = ("Documents", "AppData", ".wslconfig")
SCRIPTS = ROOT / "home/.chezmoiscripts"
TERMINAL_SETTINGS = "AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json"
TERMINAL_FIXTURE = ROOT / "script/tests/fixtures/windows-terminal-settings.json"
PS51_PROFILE_GUID = "{61c54bbd-c2c6-5271-96e7-009a87ff44bf}"
# 提示文字(要跟 config 樣板一字不差,同 test_tool_status.py)
USE_PROMPT = "用途：按一個字母（full 完整／minimal 精簡：只要 shell 體驗／custom 自訂）"
TOOLS_PROMPT = "選裝工具（空白鍵勾選、Enter 確定；用途選錯按 Ctrl+C 重來）"
# Windows 的精簡:精簡扣掉裝不了的 zsh(PowerShell 是 Windows 的 shell)
WINDOWS_LEAN = ["starship", "eza", "fzf", "bat", "ripgrep", "vim", "fastfetch"]
# Windows 可裝的(獨立的期望值):mise 裝得到的 CLI(herdr #309、snapclient #326、playwright-cli #327 見 mise-tools),
# 加 winget 裝的 tailscale、headless-chrome(#327),加官方 install.ps1 裝的 coding agent(claude #316、codex #317)
# 與 skillshare(agent-config #321),加 mise 的 npm backend 裝的 opencode(#318),加 mise 的 aqua backend 裝的 codegraph(#323),
# 加 wakatime(#324:wakatime-cli 放官方位置 ~/.wakatime,plugin 由 claude、codex 裝),加 mise 裝的 runtime uv(#341),
# 加 mise 的 pipx backend 裝的 windows-mcp(#343)
WINDOWS_FULL = {"starship", "eza", "fzf", "bat", "ripgrep", "vim", "fastfetch",
                "gh", "cloudflared", "ttyd", "ffmpeg", "node", "uv", "herdr", "bottom", "snapclient", "tailscale",
                "headless-chrome", "playwright-cli", "claude", "codex", "opencode", "agent-config", "codegraph",
                "wakatime", "windows-mcp"}
# 官方 install.ps1 裝的 coding agent:勾選名 -> (官方腳本網址, 官方裝的位置)。位置是官方文件／installer 寫的,
# claude:code.claude.com/docs/en/setup;codex:chatgpt.com/codex/install.ps1 的 $defaultVisibleBinDir
OFFICIAL_INSTALLERS = {
    "claude": ("https://claude.ai/install.ps1", r"Join-Path $HOME '.local\bin\claude.exe'"),
    "codex": ("https://chatgpt.com/codex/install.ps1", r"Join-Path $env:LOCALAPPDATA 'Programs\OpenAI\Codex\bin\codex.exe'"),
}


def parse_jsonc(text):
    """fixture 只有整行的 // 註解,拿掉就是 JSON。"""
    return json.loads("\n".join(l for l in text.splitlines() if not l.strip().startswith("//")))


def parents(paths):
    """每個 target 的上層目錄(chezmoi managed 會把它們也列出來)。"""
    return {str(p) for t in paths for p in PurePosixPath(t).parents if str(p) != "."}


class WindowsDeployTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = Path(self.tmp.name) / "home"
        self.home.mkdir()
        self.cfg = Path(self.tmp.name) / "chezmoi.toml"
        self.cfg.write_text("", encoding="utf-8")

    def tearDown(self):
        self.tmp.cleanup()

    def chezmoi(self, os_name, *args, data=None):
        info = {"os": os_name, "homeDir": str(self.home)}
        if os_name == "windows":
            # 真的 Windows 沒有 kernel 欄位。在 WSL 跑測試時它帶著 microsoft,is-wsl 會把這台也算成 wsl,
            # tailscale 變成「不建議」而掉出預設組合
            info["kernel"] = {"osrelease": ""}
        override = {"chezmoi": info} | (data or {})
        return subprocess.run([
            "chezmoi", "--no-tty", "--source", str(ROOT), "--config", str(self.cfg),
            "--destination", str(self.home), "--override-data", json.dumps(override), *args,
        ], stdin=subprocess.DEVNULL, capture_output=True, text=True, check=True).stdout

    def managed(self, os_name, tools):
        return set(self.chezmoi(os_name, "managed", data={"tools": tools}).split())

    # ===============================================================
    # 部署哪些 target
    # ===============================================================
    def test_windows_manages_exactly_the_whitelist(self):
        # 裝不了的(zsh)不會放行 sh 腳本或設定目錄;claude 勾了才放 settings.json(#319)。
        # opencode、agent-config 勾了才放它們的設定;Linux 那份 ~/.config/skillshare 永遠不放
        # (Windows 上有那個目錄,skillshare 會把它整個搬到 %AppData%)
        base = WINDOWS_TARGETS | parents(WINDOWS_TARGETS) | WINDOWS_SCRIPTS
        opencode = OPENCODE_TARGETS | parents(OPENCODE_TARGETS)
        skillshare = {SKILLSHARE_CONFIG} | parents([SKILLSHARE_CONFIG])
        codex = CODEX_TARGETS | parents(CODEX_TARGETS)
        claude = {CLAUDE_SETTINGS} | parents([CLAUDE_SETTINGS])
        # .wakatime.cfg 要有 API key 才管(test_wakatime_cfg_managed_only_with_api_key),這裡沒帶 key
        for tools, extra in (([], set()), (WINDOWS_LEAN, set()),
                             (sorted(WINDOWS_FULL), opencode | skillshare | claude | codex), (["codex"], codex),
                             (["zsh", "claude", "tailscale"], claude), (["opencode"], opencode),
                             (["agent-config"], skillshare), (["wakatime"], set())):
            with self.subTest(tools=tools):
                self.assertEqual(self.managed("windows", tools), base | extra)

    def test_linux_and_termux_skip_windows_only_targets(self):
        for os_name in ("linux", "android"):
            for tools in ([], ["zsh", "starship", "claude", "agent-config"]):
                with self.subTest(os=os_name, tools=tools):
                    leaked = {t for t in self.managed(os_name, tools)
                              if PurePosixPath(t).parts[0] in WINDOWS_ONLY or t.endswith(".ps1")}
                    self.assertEqual(leaked, set())

    def render_opencode_json(self, existing):
        """Windows 上 chezmoi 算出的 ~/.config/opencode/opencode.json(existing = None 是檔案不存在)。"""
        target = self.home / ".config/opencode/opencode.json"
        if existing is not None:
            target.parent.mkdir(parents=True)
            target.write_text(existing, encoding="utf-8")
        return json.loads(self.chezmoi("windows", "cat", str(target),
                                       data={"tools": ["opencode"], "codexLbApiKey": "fixture"}))

    def test_windows_opencode_json_is_repo_version_and_keeps_mcp(self):
        # Linux 那份是 sh + jq 的 modify_ 腳本,Windows 跑不了;Windows 渲染成 modify-template(同 Terminal 的 settings.json):
        # 內容跟 Linux 同一份 JSON,mcp 照現有檔案留著(skillshare 管的),其他 key 換回 repo 的
        fresh = self.render_opencode_json(None)
        self.assertEqual(fresh["mcp"], {})
        self.assertEqual(fresh["plugin"], ["opencode-wakatime", "oh-my-opencode-slim"])
        self.assertEqual(fresh["provider"]["codex-lb-gcp"]["options"]["apiKey"], "fixture")
        self.assertEqual(fresh["model"], "codex-lb-gcp/gpt-6.1-sol")
        self.assertEqual(fresh["small_model"], "codex-lb-gcp/gpt-6-luna")
        existing = json.dumps({"mcp": {"gh_grep": {"type": "remote", "url": "https://mcp.grep.app"}},
                               "model": "someone/else", "theme": "x"})
        kept = self.render_opencode_json(existing)
        self.assertEqual(kept["mcp"], {"gh_grep": {"type": "remote", "url": "https://mcp.grep.app"}})
        self.assertEqual(kept, fresh | {"mcp": kept["mcp"]})

    # ===============================================================
    # Codex 的 config.toml(#320):Linux 那份是 sh + python3,Windows 渲染成 modify-template,行為一樣
    # ===============================================================
    def codex_windows(self, existing):
        """Windows 上 chezmoi 算出的 ~/.codex/config.toml(existing = None 是檔案不存在)。"""
        target = self.home / ".codex/config.toml"
        target.unlink(missing_ok=True)
        if existing is not None:
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(existing, encoding="utf-8")
        return self.chezmoi("windows", "cat", str(target), data={"tools": ["codex"], "codexLbApiKey": "fixture"})

    def codex_linux(self, existing):
        script = self.chezmoi("linux", "execute-template", CODEX_CONFIG.read_text(encoding="utf-8"),
                              data={"tools": ["codex"], "codexLbApiKey": "fixture"})
        return subprocess.run(["sh", "-c", script], input=existing, text=True, capture_output=True, check=True,
                              env={"PATH": os.environ["PATH"], "HOME": str(self.home)}).stdout

    def test_windows_codex_config_pins_values_and_keeps_codex_state(self):
        out = self.codex_windows(CODEX_EXISTING)
        config, before = tomllib.loads(out), tomllib.loads(CODEX_EXISTING)
        self.assertEqual(config["model"], "gpt-6.1-sol")
        self.assertEqual(config["model_provider"], "codex-lb-gcp")
        self.assertEqual(config["approvals_reviewer"], "auto_review")
        self.assertEqual(config["model_providers"]["codex-lb-gcp"]["experimental_bearer_token"], "fixture")
        self.assertTrue(config["developer_instructions"].startswith("使用者自己的指引\n[features]\n照留。\n\n"))
        self.assertEqual(config["developer_instructions"].count("Co-authored-by: Codex <noreply@openai.com>"), 1)
        for key in ("notify", "projects", "tui", "features", "mcp_servers"):
            self.assertEqual(config[key], before[key], key)
        self.assertNotIn("skills", config)
        self.assertEqual(self.codex_windows(out), out)

    def test_windows_codex_config_matches_linux_for_same_input(self):
        # 同一批輸入,Windows 的 modify-template 跟 Linux 的 sh + python3 輸出要逐字一樣
        cases = [None, "", CODEX_EXISTING,
                 '"developer_instructions" = "a\\n\\n<!-- chezmoi:codex-commit-attribution:start -->\\nold\\n'
                 '<!-- chezmoi:codex-commit-attribution:end -->\\nb"\nnotify = ["x"]\n',
                 '[projects."/x"]\ntrust_level = "trusted"\n\n\n[mcp_servers.a]\nurl = "u"\n',
                 # 舊版 chezmoi 寫的停用 skill 橫幅在中間、table 名稱帶空白與引號、值裡有括號
                 '[projects."/x"]\ntrust_level = "trusted"\n\n# ' + '=' * 60 + '\n# 由 chezmoi 停用的 skill(obsidian-wiki 那包)。\n'
                 '# ' + '=' * 60 + '\n\n[[skills.config]]\npath = "/w/SKILL.md"\nenabled = false\n\n'
                 '[ model_providers . "codex-lb-gcp" ]\nname = "x"\n\n[mcp_servers.b]\ncommand = "a[b"\nargs = ["{", "#"]\n']
        for existing in cases:
            with self.subTest(existing=(existing or "")[:40]):
                linux = self.codex_linux(existing or "")
                self.assertEqual(self.codex_windows(existing), linux)
                self.assertEqual(self.codex_windows(linux), linux)

    def render(self, path, tools):
        """在 Windows 渲染 repo 裡的一個樣板(path 相對 repo 根目錄)。"""
        return self.chezmoi("windows", "execute-template", (ROOT / path).read_text(encoding="utf-8"),
                            data={"tools": tools})

    # ===============================================================
    # ssh config:跟 Linux 同一份
    # ===============================================================
    def test_windows_ssh_config_has_no_userspace_proxycommand(self):
        # userspace tailscale 只有沒 root 的 Linux 才有;Windows 走系統的 Tailscale,勾了 tailscale 也不加
        for tools in ([], ["tailscale"]):
            with self.subTest(tools=tools):
                out = self.render("home/private_dot_ssh/private_config.tmpl", tools)
                self.assertIn("Host company-ec2\n", out)
                self.assertNotIn("ProxyCommand", out)

    def test_cross_tailnet_hosts_use_full_magicdns_name(self):
        # 短名只有同一個 tailnet 解析得到;公司 tailnet 的機器分享到個人 tailnet 後要完整名稱(#307)
        out = self.render("home/private_dot_ssh/private_config.tmpl", [])
        hostnames = dict(re.findall(r"^Host (\S+)\n    HostName (\S+)$", out, re.M))
        for host, device in (("lianghua", "lianghua"), ("pos2-dev", "pos2-dev"), ("company-ec2", "aws-ec2-henry")):
            with self.subTest(host=host):
                self.assertEqual(hostnames[host], f"{device}.tail29dcee.ts.net")

    # ===============================================================
    # Windows 的 .ps1 腳本:winget 裝 app、mise 裝 CLI、最後列出略過的
    # ===============================================================

    def mise_list(self, tools):
        out = self.render("home/dot_config/mise/conf.d/dotfiles.toml.tmpl", tools)
        return {l.split(" = ")[0].strip('"') for l in out.splitlines() if " = " in l and not l.startswith("#")}

    def test_windows_minimal_installs_cli_with_mise(self):
        # #275 驗收:選精簡 apply 後 starship、fastfetch、zoxide 由 mise 裝好
        self.assertEqual(self.mise_list(WINDOWS_LEAN),
                         {"starship", "eza", "fzf", "bat", "ripgrep", "vim", "fastfetch", "zoxide"})

    def test_windows_mise_skips_unsupported_and_winget_tools(self):
        # zoxide 不看勾選;tailscale 走 winget;btop 裝不了
        self.assertEqual(self.mise_list(["tailscale", "btop", "gh"]), {"zoxide", "gh"})

    def test_windows_claude_brings_poppler_for_pdf_pages(self):
        # Claude Code 照頁數讀 PDF 要 pdftoppm,官方要 Windows 自己裝一份 poppler(#316):
        # 勾 claude 就由 mise 裝 conda 的 poppler;claude 本體走官方 install.ps1,不進 mise
        self.assertEqual(self.mise_list(["claude"]), {"zoxide", "poppler"})

    def test_windows_codex_not_in_mise(self):
        # codex 本體走官方 install.ps1(#317),mise 不裝;mise 裝的那份 codex update 認不出安裝方式
        self.assertEqual(self.mise_list(["codex"]), {"zoxide"})

    def test_windows_herdr_installs_with_mise(self):
        # herdr 有 Windows 版,mise 的 registry 有它(#309);Linux 走官方 installer,不進 mise 清單
        self.assertEqual(self.mise_list(["herdr"]), {"zoxide", "herdr"})
        linux = self.chezmoi("linux", "execute-template",
                             (ROOT / "home/.chezmoitemplates/mise-tools").read_text(encoding="utf-8"),
                             data={"tools": ["herdr"]})
        self.assertNotIn("herdr", linux)

    def test_windows_bottom_installs_with_mise_and_btop_points_to_it(self):
        # bottom 的 release 有 Windows 版(#325);btop 只有 Linux 版,選單上叫人改勾 bottom
        self.assertEqual(self.mise_list(["bottom", "btop"]), {"zoxide", "bottom"})
        btop = next(l for l in self.labels() if l.startswith("btop "))
        self.assertIn("（裝不了：", btop)
        self.assertIn("改勾 bottom", btop)

    def test_windows_playwright_cli_installs_with_mise_npm_and_node(self):
        # #327:官方裝法是 npm 全域套件,Windows 走 mise 的 npm backend;它要 Node,沒勾 node 也列 LTS。
        # Linux 從 #342 起也走 mise 的 npm backend
        self.assertEqual(self.mise_list(["playwright-cli"]), {"zoxide", "npm:@playwright/cli", "node"})
        linux = self.chezmoi("linux", "execute-template",
                             (ROOT / "home/.chezmoitemplates/mise-tools").read_text(encoding="utf-8"),
                             data={"tools": ["playwright-cli"]})
        self.assertEqual(set(linux.split()), {'"node"', '"npm:@playwright/cli"', '"lts"', '"latest"', "="})

    def test_windows_opencode_installs_v1_with_mise_npm_and_node(self):
        # #318:OpenCode 沒有 Windows 的 install.ps1(curl installer 在 Windows 要 Git Bash),走 mise 的 npm backend。
        # 點名 opencode-ai:這個套件只有 OpenCode 1,跟 Linux 的 opencode.ai/install 同一個大版本;
        # registry 的短名 opencode 已經指到 OpenCode 2(@opencode/cli)。它要 Node,沒勾 node 也列 LTS。
        # Linux 照舊官方 installer,不進 mise 清單
        self.assertEqual(self.mise_list(["opencode"]), {"zoxide", "npm:opencode-ai", "node"})
        linux = self.chezmoi("linux", "execute-template",
                             (ROOT / "home/.chezmoitemplates/mise-tools").read_text(encoding="utf-8"),
                             data={"tools": ["opencode"]})
        self.assertNotIn("opencode", linux)

    def test_windows_opencode_runs_its_postinstall(self):
        # mise 的 npm backend 預設不跑 lifecycle script:opencode-ai 的 bin/opencode.exe 是佔位檔,
        # 要 postinstall 換成平台套件裡的真執行檔(henry-desktop 實測沒跑時 opencode --version 失敗)。
        # tool option allow_builds 只放行 opencode-ai 自己的 script
        out = self.render("home/dot_config/mise/conf.d/dotfiles.toml.tmpl", ["opencode"])
        self.assertIn('"npm:opencode-ai" = { version = "latest", allow_builds = ["opencode-ai"] }', out)

    def test_windows_codegraph_installs_release_bundle_with_mise_without_node(self):
        # #323:registry 的短名 codegraph 是 aqua:colbymchenry/codegraph,裝 GitHub release 的 bundle(自帶 Node runtime),
        # 所以不連帶列 Node LTS;shim 是 codegraph.exe,MCP 設定的 command: codegraph 找得到。
        # Linux 從 #342 起走 mise 的 npm backend(不是 aqua),連帶列 Node LTS
        self.assertEqual(self.mise_list(["codegraph"]), {"zoxide", "codegraph"})
        linux = self.chezmoi("linux", "execute-template",
                             (ROOT / "home/.chezmoitemplates/mise-tools").read_text(encoding="utf-8"),
                             data={"tools": ["codegraph"]})
        self.assertEqual(linux.split(), ['"npm:@colbymchenry/codegraph"', "=", '"latest"', '"node"', "=", '"lts"'])

    def test_windows_wakatime_brings_node_lts_for_plugin_hooks(self):
        # #324:Claude Code、Codex 的 WakaTime plugin 用 PATH 上的 node 跑 hook,Windows 的 Node 由 mise 的 LTS 提供;
        # wakatime-cli 不進 mise:plugin 只認 ~/.wakatime 底下官方位置那支
        self.assertEqual(self.mise_list(["wakatime"]), {"zoxide", "node"})
        self.assertEqual(self.render(SCRIPTS / "run_onchange_after_zz-env-skipped.ps1.tmpl", ["wakatime"]).strip(), "")

    def test_windows_mcp_installs_with_mise_pipx_and_uv(self):
        # #343:windows-mcp 是 PyPI 套件,mise 的 pipx backend 有 uv 就用 uv tool install,uv 在同一份清單時先裝 uv
        # (https://mise.jdx.dev/dev-tools/backends/pypi.html)。沒勾 uv 也要列 uv,不然 mise 找不到 uv 會改要 pipx 而失敗
        self.assertEqual(self.mise_list(["windows-mcp"]), {"zoxide", "pipx:windows-mcp", "uv"})
        self.assertEqual(self.render(SCRIPTS / "run_onchange_after_zz-env-skipped.ps1.tmpl", ["windows-mcp"]).strip(), "")
        linux = self.chezmoi("linux", "execute-template",
                             (ROOT / "home/.chezmoitemplates/mise-tools").read_text(encoding="utf-8"),
                             data={"tools": ["windows-mcp"]})
        self.assertNotIn("windows-mcp", linux)
        self.assertNotIn('"uv"', linux)

    def test_windows_node_installs_lts_with_mise(self):
        # mise 在 Windows 裝得了 Node:勾了 node 就列 LTS,不再算略過
        out = self.render("home/dot_config/mise/conf.d/dotfiles.toml.tmpl", ["node"])
        self.assertIn('"node" = "lts"', out)
        self.assertEqual(self.render(SCRIPTS / "run_onchange_after_zz-env-skipped.ps1.tmpl", ["node"]).strip(), "")

    def test_windows_winget_installs_base_apps_and_ticked_tailscale(self):
        script = SCRIPTS / "run_onchange_before_install-packages-windows.ps1.tmpl"
        base = self.render(script, [])
        for app in ("jdx.mise", "Microsoft.PowerShell", "Microsoft.WindowsTerminal"):
            self.assertIn(f"'{app}'", base)
        self.assertNotIn("Tailscale.Tailscale", base)
        self.assertIn("'Tailscale.Tailscale'", self.render(script, ["tailscale"]))

    def test_windows_headless_chrome_is_googles_regular_installer(self):
        # #327:Windows 的 headless-chrome 就是 Chrome 本身(--headless)。用一般 installer 的 Google.Chrome.EXE:
        # 從官網裝的 Chrome 在 winget list 對到它,不是企業版 MSI 的 Google.Chrome(lianghua 實查),已經有就跳過
        script = SCRIPTS / "run_onchange_before_install-packages-windows.ps1.tmpl"
        self.assertNotIn("Google.Chrome", self.render(script, []))
        out = self.render(script, ["headless-chrome"])
        ids = re.search(r"^\$ids = @\((.*?)^\)", out, re.M | re.S).group(1)
        self.assertIn("'Google.Chrome.EXE'", ids)
        self.assertNotIn("'Google.Chrome'", ids)

    def test_windows_chrome_from_enterprise_msi_counts_as_installed(self):
        # #351:公司派發的企業版 MSI(winget id Google.Chrome)也算已經有 Chrome,跳過,不再 install 一份(exit 3)
        script = SCRIPTS / "run_onchange_before_install-packages-windows.ps1.tmpl"
        self.assertIn("'Google.Chrome.EXE' = @('Google.Chrome')", self.render(script, ["headless-chrome"]))

    def test_windows_mise_script_runs_mise_install(self):
        out = self.render(SCRIPTS / "run_onchange_after_install-mise.ps1.tmpl", WINDOWS_LEAN)
        self.assertIn("mise install", out)
        # 清單在腳本裡(註解),清單變了 run_onchange_ 才會重跑
        self.assertIn('"zoxide" = "latest"', out)
        # 取消勾選的工具(#330):install 之後 prune,沒有設定檔要的版本連 shim 一起刪
        self.assertIn("mise prune --yes", out)
        self.assertLess(out.index("mise install"), out.index("mise prune --yes"))

    def test_windows_skip_summary_lists_unsupported_ticked_tools(self):
        script = SCRIPTS / "run_onchange_after_zz-env-skipped.ps1.tmpl"
        self.assertEqual(self.render(script, WINDOWS_LEAN).strip(), "")
        out = self.render(script, ["code-server", "zsh", "fzf"])
        # 中文訊息用 base64 放進腳本(渲染結果只能有 ASCII,見下一個測試)
        decoded = "\n".join(base64.b64decode(b).decode("utf-8")
                            for b in re.findall(r"'([A-Za-z0-9+/]{8,}={0,2})'", out))
        self.assertIn("== 這台裝不了,以下選裝工具已略過(其餘照常裝好;要改勾選打 tools):", decoded)
        self.assertIn("code-server", decoded)
        self.assertIn("code-server 官方不出 Windows 版，到 WSL 裝", decoded)
        self.assertIn("zsh", decoded)
        self.assertNotIn("fzf", decoded)

    def test_windows_snapclient_installs_official_zip_with_mise_and_vcredist(self):
        # 官方 release 的 snapclient_win64.zip(#326):mise github backend 點名這個 asset,只把 snapclient.exe
        # 放上 PATH;exe 要 MSVC runtime、壓縮檔沒附那幾個 DLL,VC++ redistributable 由 winget 裝。勾了不再算略過
        out = self.render("home/dot_config/mise/conf.d/dotfiles.toml.tmpl", ["snapclient"])
        self.assertIn('"github:badaix/snapcast" = { version = "latest", asset_pattern = "snapclient_win64.zip", '
                      'filter_bins = "snapclient.exe" }', out)
        winget = SCRIPTS / "run_onchange_before_install-packages-windows.ps1.tmpl"
        self.assertIn("'Microsoft.VCRedist.2015+.x64'", self.render(winget, ["snapclient"]))
        self.assertNotIn("VCRedist", self.render(winget, []))
        self.assertEqual(self.render(SCRIPTS / "run_onchange_after_zz-env-skipped.ps1.tmpl", ["snapclient"]).strip(), "")
        # Linux 照舊 apt,不進 mise 清單
        linux = self.chezmoi("linux", "execute-template",
                             (ROOT / "home/.chezmoitemplates/mise-tools").read_text(encoding="utf-8"),
                             data={"tools": ["snapclient"]})
        self.assertNotIn("snapcast", linux)

    # ===============================================================
    # coding agent:官方 install.ps1(#316 claude、#317 codex)
    # ===============================================================
    def agent_script(self, tool):
        # #334 起兩個 agent 同一支(install-official.ps1,照選裝工具表跑)
        return SCRIPTS / "run_onchange_after_install-official.ps1.tmpl"

    def test_windows_agent_script_empty_when_not_ticked(self):
        for tools in ([], WINDOWS_LEAN):
            with self.subTest(tools=tools):
                self.assertEqual(self.render(self.agent_script("claude"), tools).strip(), "")
        # 只勾另一個:不跑這個的 installer
        for tool, (url, _) in OFFICIAL_INSTALLERS.items():
            others = [t for t in OFFICIAL_INSTALLERS if t != tool]
            with self.subTest(tool=tool, tools=others):
                self.assertNotIn(url, self.render(self.agent_script(tool), others))

    def test_windows_agent_script_downloads_official_installer_then_runs_it(self):
        for tool, (url, _) in OFFICIAL_INSTALLERS.items():
            with self.subTest(tool=tool):
                out = self.render(self.agent_script(tool), [tool])
                # 先下載成檔案再跑:接 pipe(irm | iex)的話下載失敗看不出來
                self.assertNotIn("| iex", out)
                self.assertNotIn("Invoke-Expression", out)
                download = out.index(url)
                self.assertIn("-OutFile", out[download:])
                self.assertLess(download, out.index("& $installer"))

    def test_windows_agent_script_skips_when_official_install_exists(self):
        # 只認官方裝的位置:mise、winget 那份(PATH 上的同名指令)不算,不然會被它擋住而不裝官方版
        for tool, (url, exe) in OFFICIAL_INSTALLERS.items():
            with self.subTest(tool=tool):
                out = self.render(self.agent_script(tool), [tool])
                self.assertIn(f"Test-Path ({exe})", out)
                self.assertLess(out.index("Test-Path"), out.index(url))
                self.assertNotIn(f"Get-Command {tool}", out)

    def test_windows_codex_installer_runs_non_interactive(self):
        # 官方 install.ps1 最後會問「Start Codex now?」(Read-Host),apply 會停在那裡;CODEX_NON_INTERACTIVE=1 才不問
        out = self.render(self.agent_script("codex"), ["codex"])
        self.assertLess(out.index("$env:CODEX_NON_INTERACTIVE = '1'"), out.index("& $installer"))

    # ===============================================================
    # wakatime(#324):wakatime-cli 放官方位置,有勾的 agent 裝 plugin
    # ===============================================================
    WAKATIME_SCRIPT = SCRIPTS / "run_onchange_after_install-wakatime.ps1.tmpl"

    def test_windows_wakatime_script_empty_when_not_ticked(self):
        for tools in ([], WINDOWS_LEAN, ["claude", "codex"]):
            with self.subTest(tools=tools):
                self.assertEqual(self.render(self.WAKATIME_SCRIPT, tools).strip(), "")

    def test_windows_wakatime_cli_goes_to_official_location(self):
        # 兩個 plugin 找 %USERPROFILE%\.wakatime\wakatime-cli-windows-<arch>.exe(官方 release 的 zip 裡就是這個檔名);
        # 已經有就跳過,在下載之前
        out = self.render(self.WAKATIME_SCRIPT, ["wakatime"])
        self.assertIn("$dir = Join-Path $HOME '.wakatime'", out)
        self.assertIn("'wakatime-cli-windows-amd64.exe'", out)
        url = "https://github.com/wakatime/wakatime-cli/releases/latest/download/wakatime-cli-windows-amd64.zip"
        download = out.index(url)
        self.assertLess(out.index("Test-Path $bin"), download)
        self.assertIn("-OutFile", out[download:])
        self.assertLess(download, out.index("Expand-Archive"))
        # codex 的 plugin 在 Windows 把 wakatime-cli.exe 做成複製(Linux 是 symlink)
        self.assertIn("Join-Path $dir 'wakatime-cli.exe'", out)

    def test_windows_wakatime_plugins_only_for_ticked_agents(self):
        claude = "plugin marketplace add https://github.com/wakatime/claude-code-wakatime.git"
        codex = "plugin marketplace add wakatime/codex-cli-wakatime"
        for tools, want in ((["wakatime"], set()), (["wakatime", "claude"], {claude}),
                            (["wakatime", "codex"], {codex}), (["wakatime", "claude", "codex"], {claude, codex})):
            with self.subTest(tools=tools):
                out = self.render(self.WAKATIME_SCRIPT, tools)
                self.assertEqual({c for c in (claude, codex) if c in out}, want)

    def test_windows_wakatime_plugins_skip_when_installed(self):
        # 已裝就跳過(重跑也只印 already,但會連 GitHub);判斷照 plugin list --json 的欄位,同 Linux
        out = self.render(self.WAKATIME_SCRIPT, ["wakatime", "claude", "codex"])
        for listing, plugin_id, install in (
                ("Get-PluginList $claude", "'claude-code-wakatime@wakatime'",
                 "& $claude plugin install claude-code-wakatime@wakatime"),
                ("(Get-PluginList $codex).installed", "'codex-cli-wakatime@wakatime'",
                 "& $codex plugin add codex-cli-wakatime@wakatime")):
            with self.subTest(plugin=plugin_id):
                self.assertLess(out.index(listing), out.index(plugin_id))
                self.assertLess(out.index(plugin_id), out.index(install))
        # 找不到 agent 時找官方 installer 裝的位置(chezmoi 跑腳本的 PATH 不一定有)
        self.assertIn(r"Join-Path $HOME '.local\bin\claude.exe'", out)
        self.assertIn(r"Join-Path $env:LOCALAPPDATA 'Programs\OpenAI\Codex\bin\codex.exe'", out)

    def test_wakatime_cfg_managed_only_with_api_key(self):
        # 沒填 API key(或沒問過)時 chezmoi 不管 ~/.wakatime.cfg。管了又渲染成空的,chezmoi 會把現有的檔刪掉:
        # henry-desktop 第一次 init 時 key 留空,原本能用的 .wakatime.cfg 就這樣被刪(#324)。
        # Linux 用同一份樣板,同樣要擋
        for os_name in ("windows", "linux"):
            for data in ({"tools": ["wakatime"]}, {"tools": ["wakatime"], "wakatimeApiKey": ""}):
                with self.subTest(os=os_name, data=data):
                    managed = set(self.chezmoi(os_name, "managed", data=data).split())
                    self.assertNotIn(WAKATIME_CFG, managed)
            with self.subTest(os=os_name, key="set"):
                data = {"tools": ["wakatime"], "wakatimeApiKey": "waka_fixture"}
                self.assertIn(WAKATIME_CFG, set(self.chezmoi(os_name, "managed", data=data).split()))
                self.assertIn("api_key = waka_fixture",
                              self.chezmoi(os_name, "cat", str(self.home / WAKATIME_CFG), data=data))

    # ===============================================================
    # agent-config:官方 install.ps1 裝 skillshare,init 後 sync(#321)
    # ===============================================================
    AGENT_SCRIPTS = (SCRIPTS / "run_onchange_after_install-agent-config.ps1.tmpl",
                     SCRIPTS / "run_onchange_after_sync-skillshare.ps1.tmpl")

    def test_windows_agent_config_scripts_empty_when_not_ticked(self):
        for script in self.AGENT_SCRIPTS:
            for tools in ([], WINDOWS_LEAN, ["claude"]):
                with self.subTest(script=script.name, tools=tools):
                    self.assertEqual(self.render(script, tools).strip(), "")

    def test_windows_agent_config_skips_initialized_then_installs_official_then_inits(self):
        out = self.render(SCRIPTS / "run_onchange_after_install-agent-config.ps1.tmpl", ["agent-config"])
        # 已經 init 過(%AppData%\skillshare\.git)就跳過,在下載之前
        skip = out.index("Join-Path $dir '.git'")
        self.assertIn("$dir = Join-Path $env:APPDATA 'skillshare'", out)
        url = "https://raw.githubusercontent.com/runkids/skillshare/main/install.ps1"
        download = out.index(url)
        self.assertLess(skip, download)
        # 先下載成檔案再跑,不接 pipe
        self.assertIn("-OutFile", out[download:])
        self.assertNotIn("| iex", out)
        self.assertNotIn("Invoke-Expression", out)
        run = out.index("& $installer")
        self.assertLess(download, run)
        # 官方 installer 裝的位置
        self.assertIn(r"Join-Path $env:LOCALAPPDATA 'Programs\skillshare\skillshare.exe'", out)
        # remote 走 HTTPS,init 不照 --targets 加,最後 sync --all(含 MCP 與指令檔)
        self.assertIn("'https://github.com/henry5720/agent-config.git'", out)
        steps = [out.index(s) for s in ("Invoke-Skillshare init --git-root root --remote $remote --no-copy "
                                        "--no-skill --no-targets\n", "Invoke-Skillshare install -g\n",
                                        "Invoke-Skillshare sync --all\n")]
        self.assertEqual(steps, sorted(steps))
        self.assertLess(run, steps[0])

    def test_windows_agent_config_brings_git_for_skillshare_init(self):
        # skillshare init --remote 要系統的 git;Windows 基底沒有,勾 agent-config 由 winget 裝(已經有就跳過)
        winget = SCRIPTS / "run_onchange_before_install-packages-windows.ps1.tmpl"
        self.assertIn("'Git.Git'", self.render(winget, ["agent-config"]))
        self.assertNotIn("Git.Git", self.render(winget, []))
        # 剛裝的 git 不在 apply 這個 process 的 PATH:install-agent-config 先接上登錄檔的 PATH 再找 git
        out = self.render(SCRIPTS / "run_onchange_after_install-agent-config.ps1.tmpl", ["agent-config"])
        self.assertLess(out.index("GetEnvironmentVariable('Path', 'Machine')"), out.index("Get-Command git"))

    def test_windows_wakatime_brings_git_for_plugin_marketplace(self):
        # claude plugin marketplace add <git URL> 要系統的 git:勾 wakatime 也由 winget 裝 Git.Git;
        # 跟 agent-config 一起勾只裝一次
        winget = SCRIPTS / "run_onchange_before_install-packages-windows.ps1.tmpl"
        self.assertEqual(self.render(winget, ["claude", "wakatime"]).count("'Git.Git'"), 1)
        self.assertEqual(self.render(winget, ["agent-config", "claude", "wakatime"]).count("'Git.Git'"), 1)
        # 剛裝的 git 不在 apply 這個 process 的 PATH:先接上登錄檔的 PATH 再叫 claude 加 marketplace
        out = self.render(self.WAKATIME_SCRIPT, ["wakatime", "claude"])
        self.assertLess(out.index("GetEnvironmentVariable('Path', 'Machine')"),
                        out.index("& $claude plugin marketplace add"))

    def test_windows_skillshare_sync_reruns_when_checked_clients_change(self):
        # run_onchange_:釘的 targets、extras 照勾的 client 產生,勾選變了腳本內容就變,chezmoi 才重跑 sync --all
        script = SCRIPTS / "run_onchange_after_sync-skillshare.ps1.tmpl"
        only_claude = self.render(script, ["agent-config", "claude"])
        self.assertIn("& $ss sync --all", only_claude)
        self.assertNotEqual(only_claude, self.render(script, ["agent-config", "claude", "codex"]))
        self.assertEqual(only_claude, self.render(script, ["agent-config", "claude", "fzf"]))

    # ===============================================================
    # Windows 的 Git 預設 core.autocrlf=true:source checkout 成 CRLF,modify-template 的輸出不能跟著帶 \r
    # ===============================================================
    def crlf_source(self):
        """repo 的 home/ 複製一份、文字檔換成 CRLF,模擬 Windows 上 autocrlf=true 的 checkout。"""
        src = Path(self.tmp.name) / "crlf-source"
        (src / "home").mkdir(parents=True)
        (src / ".chezmoiroot").write_bytes((ROOT / ".chezmoiroot").read_bytes())
        for f in (ROOT / "home").rglob("*"):
            dest = src / f.relative_to(ROOT)
            if f.is_dir():
                dest.mkdir(parents=True, exist_ok=True)
                continue
            data = f.read_bytes()
            if b"\0" not in data:
                data = data.replace(b"\r\n", b"\n").replace(b"\n", b"\r\n")
            dest.write_bytes(data)
        return src

    def cat_bytes(self, target, existing, tools, source):
        """把 existing(bytes)放到 target,回傳 chezmoi cat 算出的 bytes。"""
        path = self.home / target
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(existing)
        info = {"os": "windows", "homeDir": str(self.home), "kernel": {"osrelease": ""}}
        return subprocess.run([
            "chezmoi", "--no-tty", "--source", str(source), "--config", str(self.cfg),
            "--destination", str(self.home), "--override-data",
            json.dumps({"chezmoi": info, "tools": tools, "codexLbApiKey": "fixture"}), "cat", str(path),
        ], stdin=subprocess.DEVNULL, capture_output=True, check=True).stdout

    def test_windows_skillshare_config_keeps_skillshare_bytes_from_crlf_checkout(self):
        # skillshare 存的檔案(LF)已經是釘的內容:CRLF 或 LF 的 checkout 渲染出來都要逐 byte 一樣,chezmoi diff 才是空的
        saved = SKILLSHARE_FIXTURE.read_bytes()
        tools = ["agent-config", "claude", "codex", "opencode"]
        for name, source in (("lf", ROOT), ("crlf", self.crlf_source())):
            with self.subTest(checkout=name):
                once = self.cat_bytes(SKILLSHARE_CONFIG, saved, tools, source)
                self.assertEqual(once, saved)
                self.assertEqual(self.cat_bytes(SKILLSHARE_CONFIG, once, tools, source), once)

    def test_windows_opencode_json_has_no_cr_from_crlf_checkout(self):
        # toPrettyJson 的輸出是 LF;樣板自己的換行不能漏進來(CRLF checkout 會在檔尾多一個 \r\n)
        target = ".config/opencode/opencode.json"
        lf = self.cat_bytes(target, b"", ["opencode"], ROOT)
        self.assertTrue(lf.endswith(b"}\n") and not lf.endswith(b"\n\n"))
        self.assertEqual(self.cat_bytes(target, b"", ["opencode"], self.crlf_source()), lf)

    def test_windows_codex_config_same_from_crlf_checkout(self):
        # 樣板自己的字(釘的 TOML、commit 指引)不能帶 \r 進來;codex 存的是 LF
        lf = self.cat_bytes(".codex/config.toml", CODEX_EXISTING.encode(), ["codex"], ROOT)
        self.assertNotIn(b"\r", lf)
        self.assertEqual(self.cat_bytes(".codex/config.toml", CODEX_EXISTING.encode(), ["codex"], self.crlf_source()), lf)

    def test_windows_ps1_render_ascii_only(self):
        # 第一次 apply 用 5.1 跑(config 的 interpreters.ps1),它讀沒有 BOM 的檔案用 ANSI 字碼頁
        for path, tools in ((SCRIPTS / "run_onchange_before_install-packages-windows.ps1.tmpl", ["tailscale"]),
                            (SCRIPTS / "run_onchange_after_install-mise.ps1.tmpl", sorted(WINDOWS_FULL)),
                            (SCRIPTS / "run_onchange_after_install-official.ps1.tmpl", ["claude", "codex"]),
                            (SCRIPTS / "run_onchange_after_install-wakatime.ps1.tmpl", ["wakatime", "claude", "codex"]),
                            (SCRIPTS / "run_onchange_after_install-agent-config.ps1.tmpl", ["agent-config"]),
                            (SCRIPTS / "run_onchange_after_sync-skillshare.ps1.tmpl", ["agent-config", "claude"]),
                            (SCRIPTS / "run_onchange_after_zz-env-skipped.ps1.tmpl", ["code-server", "zsh"]),
                            ("home/dot_local/bin/tools.ps1.tmpl", [])):
            with self.subTest(path=str(path)):
                out = self.render(path, tools)
                self.assertTrue(out.strip())
                self.assertTrue(out.isascii(), [l for l in out.splitlines() if not l.isascii()][:3])

    def test_windows_mcp_keys_become_user_env_vars(self):
        # Linux 由 env.zsh export;Windows 的 agent 不一定從 PowerShell 開,所以設成 User 範圍的環境變數。
        # 沒填的不動(不刪),兩個都空就渲染成空的,chezmoi 不跑。
        path = SCRIPTS / "run_onchange_after_set-mcp-env.ps1.tmpl"
        for data, want in (({}, []), ({"context7ApiKey": "", "graphifyApiKey": "g'k"}, [("GRAPHIFY_API_KEY", "g''k")]),
                           ({"context7ApiKey": "c7", "graphifyApiKey": "gk"}, [("CONTEXT7_API_KEY", "c7"), ("GRAPHIFY_API_KEY", "gk")])):
            with self.subTest(data=data):
                out = self.chezmoi("windows", "execute-template", path.read_text(encoding="utf-8"), data=data)
                self.assertTrue(out.isascii())
                self.assertEqual(re.findall(r"SetEnvironmentVariable\('(\w+)', '((?:[^']|'')*)', 'User'\)", out), want)
                if not want: self.assertEqual(out.strip(), "")

    def test_windows_ps1_scripts_drop_pwsh7_module_paths_first(self):
        # chezmoi 從 pwsh 7 跑時,5.1 繼承 pwsh 7 的 PSModulePath,Get-FileHash、Expand-Archive 載不到(#345,
        # Windows runner 實測)。每支 .ps1 第一行可執行的程式就要把它們拿掉
        for path in sorted(SCRIPTS.glob("*.ps1.tmpl")):
            with self.subTest(path=path.name):
                out = self.render(path, sorted(WINDOWS_FULL) + ["code-server", "zsh"])
                code = [l for l in out.splitlines() if l.strip() and not l.lstrip().startswith("#")]
                if not code: continue  # 渲染成空的(set-mcp-env 沒帶 key)chezmoi 不跑
                self.assertIn("$env:PSModulePath", code[0])

    def test_windows_tools_command_reprompts_and_applies(self):
        out = self.render("home/dot_local/bin/tools.ps1.tmpl", [])
        self.assertIn("chezmoi init --prompt @args", out)
        self.assertIn("chezmoi apply", out)

    def test_windows_apply_writes_codex_config_on_new_machine(self):
        # 沒有 ~/.codex 的新機器:apply 寫出釘的那幾項,再 verify 沒有差異(沒勾 codex、沒有 key 的情況見上一個測試)
        data = {"tools": ["codex"], "codexLbApiKey": "fixture"}
        self.chezmoi("windows", "apply", "--exclude", "scripts", data=data)
        config = tomllib.loads((self.home / ".codex/config.toml").read_text(encoding="utf-8"))
        self.assertEqual(config["sandbox_mode"], "workspace-write")
        self.chezmoi("windows", "verify", "--exclude", "scripts", data=data)

    def test_windows_apply_deploys_tools_and_mise_list(self):
        # 不跑腳本(--exclude scripts):Linux 上沒有 powershell
        self.chezmoi("windows", "apply", "--exclude", "scripts", data={"tools": WINDOWS_LEAN})
        self.assertTrue((self.home / ".local/bin/tools.ps1").is_file())
        self.assertIn('"zoxide" = "latest"',
                      (self.home / ".config/mise/conf.d/dotfiles.toml").read_text(encoding="utf-8"))

    # ===============================================================
    # config 樣板(chezmoi init 問什麼)
    # ===============================================================
    def init(self, use, picked=None):
        """全新 Windows 跑 config 樣板:用途選 use,picked 給選單文字(None = 選單直接 Enter)。
        stdin 是 /dev/null:沒給答案的提示(例如 git 身分)會讀到 EOF 而失敗。"""
        flags = ["--promptChoice", f"{USE_PROMPT}={use[0]}"]
        if picked is not None:
            flags += ["--promptMultichoice", f"{TOOLS_PROMPT}={'/'.join(picked)}"]
        return self.chezmoi("windows", "execute-template", "--init", *flags,
                            CONFIG_TEMPLATE.read_text(encoding="utf-8"))

    def labels(self):
        return self.chezmoi("windows", "execute-template",
                            '{{ includeTemplate "tool-menu-labels" . }}').splitlines()

    def tools_of(self, out):
        line = next(l for l in out.splitlines() if l.startswith("    tools = "))
        return json.loads(line.split("=", 1)[1])

    def test_windows_init_asks_use_and_menu(self):
        tailscale = next(l for l in self.labels() if l.startswith("tailscale "))
        out = self.init("custom", [tailscale])
        self.assertIn('\n    machineUse = "custom"\n', out)
        self.assertEqual(self.tools_of(out), ["tailscale"])
        # Windows 不部署 .gitconfig:git 身分不問(問了會讀到 EOF 失敗)
        self.assertNotIn("gitUser", out)

    def test_old_windows_config_gets_asked_on_next_init(self):
        # #275 以前 Windows 的 config 是 tools = []、沒有 machineUse:不能當成「自訂、什麼都不勾」沿用,
        # 下次 chezmoi init 要出用途與選單(這裡給 m,Enter 選單 = 精簡)
        self.cfg.write_text("[data]\n    tools = []\n    toolsSchema = 3\n", encoding="utf-8")
        out = self.init("minimal")
        self.assertIn('\n    machineUse = "minimal"\n', out)
        self.assertEqual(self.tools_of(out), WINDOWS_LEAN)

    def test_windows_minimal_is_lean_without_zsh(self):
        out = self.init("minimal")
        self.assertIn('\n    machineUse = "minimal"\n', out)
        self.assertEqual(self.tools_of(out), WINDOWS_LEAN)

    def test_windows_full_is_what_windows_can_install(self):
        out = self.init("full")
        self.assertIn('\n    machineUse = "full"\n', out)
        self.assertEqual(set(self.tools_of(out)), WINDOWS_FULL)

    def test_windows_codegraph_menu_says_bundle_without_node(self):
        # Windows 的 codegraph 是 mise 裝自帶 Node 的 release bundle(#323):選單不能說 npm 裝、一併裝 Node,
        # node 那項也不能說勾了 codegraph 會自動裝
        labels = self.labels()
        codegraph = next(l for l in labels if l.startswith("codegraph "))
        self.assertNotIn("npm", codegraph)
        self.assertNotIn("Node", codegraph)
        node = next(l for l in labels if l.startswith("node "))
        self.assertNotIn("codegraph", node)

    def test_windows_menu_lists_every_tool_and_marks_the_rest(self):
        labels = self.labels()
        menu = {l.split(" ")[0] for l in labels}
        marked = {l.split(" ")[0] for l in labels if "（裝不了：" in l}
        self.assertEqual(menu - marked, WINDOWS_FULL)
        self.assertTrue({"zsh", "btop", "code-server"} <= marked)

    def test_windows_runs_ps1_scripts_with_powershell_bypassing_policy(self):
        # 第一次 init 時 pwsh 可能還沒裝、執行原則可能是 Restricted:固定用 5.1,只對這個 process 繞過執行原則
        out = self.init("minimal")
        self.assertIn("\n[interpreters.ps1]\n", out)
        self.assertIn('    command = "powershell"\n', out)
        self.assertIn('    args = ["-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File"]\n', out)

    # ===============================================================
    # PowerShell profile(pwsh 7 與 5.1 共用一份)
    # ===============================================================
    def test_both_powershell_profiles_render_the_same_settings(self):
        self.chezmoi("windows", "apply", "--exclude", "scripts", data={"tools": []})
        pwsh7 = (self.home / "Documents/PowerShell/Profile.ps1").read_text(encoding="utf-8")
        ps51 = (self.home / "Documents/WindowsPowerShell/Profile.ps1").read_text(encoding="utf-8")
        self.assertEqual(pwsh7, ps51)
        for needle in (
            r"$HOME\.local\bin",
            "Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete",
            "Get-Command fastfetch",
            "Get-Command starship",
            "starship init powershell",
            "Get-Command zoxide",
            "zoxide init powershell",
        ):
            with self.subTest(needle=needle):
                self.assertIn(needle, pwsh7)
        self.assertNotIn("oh-my-posh", pwsh7)

    def test_profile_finds_mise_tools_before_starting_them(self):
        # starship、fastfetch、zoxide 由 mise 裝:shims 要在 Get-Command 找它們之前加進 PATH
        self.chezmoi("windows", "apply", "--exclude", "scripts", data={"tools": []})
        profile = (self.home / "Documents/PowerShell/Profile.ps1").read_text(encoding="utf-8")
        self.assertIn(r"$env:LOCALAPPDATA\mise\shims", profile)
        self.assertLess(profile.index(r"mise\shims"), profile.index("Get-Command fastfetch"))

    def test_powershell_profile_is_ascii_only(self):
        # 5.1 讀沒有 BOM 的檔案用系統 ANSI 字碼頁,UTF-8 的中文註解會變亂碼
        self.chezmoi("windows", "apply", "--exclude", "scripts", data={"tools": []})
        for target in ("Documents/PowerShell/Profile.ps1", "Documents/WindowsPowerShell/Profile.ps1"):
            with self.subTest(target=target):
                self.assertTrue((self.home / target).read_bytes().isascii())

    def test_profile_leaves_prediction_source_at_default(self):
        # pwsh 7.6 的 PSReadLine 預設就開灰字建議(HistoryAndPlugin);5.1 的 2.0 沒有這個參數,
        # 而且輸出被導向時設它會丟例外、中斷整份 profile(henry-desktop 實測),所以不設
        self.chezmoi("windows", "apply", "--exclude", "scripts", data={"tools": []})
        profile = (self.home / "Documents/PowerShell/Profile.ps1").read_text(encoding="utf-8")
        self.assertNotIn("PredictionSource", profile)

    def test_fastfetch_runs_only_in_interactive_shells(self):
        # 跟 zsh 開 shell 時跑 fastfetch 一樣;但 profile 連 pwsh -c、-File、ssh 執行指令都會載入,
        # 那些情況不能多印一張系統資訊。判斷式的實際行為在 henry-desktop 實測(Linux 沒有 pwsh)
        self.chezmoi("windows", "apply", "--exclude", "scripts", data={"tools": []})
        lines = (self.home / "Documents/PowerShell/Profile.ps1").read_text(encoding="utf-8").splitlines()
        idx = next(i for i, l in enumerate(lines) if l.strip() == "fastfetch")
        guard = next(l for l in reversed(lines[:idx]) if l.strip().startswith("if"))
        self.assertIn("Get-Command fastfetch", guard)
        self.assertIn("IsOutputRedirected", guard)
        self.assertIn("GetCommandLineArgs", "\n".join(lines[:idx]))

    # ===============================================================
    # Windows Terminal 的 settings.json(modify template)
    # ===============================================================
    # 只管 defaultProfile(pwsh 7)和 profiles.defaults.font.face(Hack Nerd Font)兩個值。
    # fixture 照 henry-desktop 的結構:有註解、key 不照字母序,兩個值都已經是對的。
    def render_terminal_settings(self, settings):
        """把 settings(None = 檔案不存在)放到 Terminal 的位置,回傳 chezmoi 算出的新內容。"""
        target = self.home / TERMINAL_SETTINGS
        if settings is not None:
            target.parent.mkdir(parents=True)
            target.write_text(settings, encoding="utf-8")
        return self.chezmoi("windows", "cat", str(target))

    def test_terminal_keeps_bytes_when_values_already_right(self):
        settings = TERMINAL_FIXTURE.read_text(encoding="utf-8")
        self.assertEqual(self.render_terminal_settings(settings), settings)

    def test_terminal_changes_only_the_two_values(self):
        settings = (TERMINAL_FIXTURE.read_text(encoding="utf-8")
                    .replace('"defaultProfile": "{574e775e-4f2a-5b96-ac1e-a2962a402336}"',
                             f'"defaultProfile": "{PS51_PROFILE_GUID}"')
                    .replace('"face": "Hack Nerd Font"', '"face": "Cascadia Mono"'))
        before = parse_jsonc(settings)
        self.assertEqual(before["defaultProfile"], PS51_PROFILE_GUID)  # fixture 真的改到了
        after = json.loads(self.render_terminal_settings(settings))
        self.assertEqual(after["defaultProfile"], "{574e775e-4f2a-5b96-ac1e-a2962a402336}")
        self.assertEqual(after["profiles"]["defaults"]["font"]["face"], "Hack Nerd Font")
        # 其他全部不變(包括 profiles.list 和同一層的 font.size)
        before["defaultProfile"] = after["defaultProfile"]
        before["profiles"]["defaults"]["font"]["face"] = "Hack Nerd Font"
        self.assertEqual(after, before)

    def test_terminal_keeps_default_profile_without_pwsh_profile(self):
        # pwsh 裝了但 Terminal 還沒開過:profiles.list 沒有 PowershellCore 的設定檔
        settings = (TERMINAL_FIXTURE.read_text(encoding="utf-8")
                    .replace('"defaultProfile": "{574e775e-4f2a-5b96-ac1e-a2962a402336}"',
                             f'"defaultProfile": "{PS51_PROFILE_GUID}"')
                    .replace('"source": "Windows.Terminal.PowershellCore"', '"source": "Somewhere.Else"')
                    .replace('"face": "Hack Nerd Font"', '"face": "Cascadia Mono"'))
        after = json.loads(self.render_terminal_settings(settings))
        self.assertEqual(after["defaultProfile"], PS51_PROFILE_GUID)
        self.assertEqual(after["profiles"]["defaults"]["font"]["face"], "Hack Nerd Font")

    def test_terminal_without_settings_writes_only_the_font(self):
        # settings.json 不存在(Terminal 沒開過):只寫得出字型,pwsh 的 guid 要等 Terminal 產生設定檔才知道
        self.assertEqual(json.loads(self.render_terminal_settings(None)),
                         {"profiles": {"defaults": {"font": {"face": "Hack Nerd Font"}}}})

    def test_terminal_leaves_old_list_style_profiles_alone(self):
        # 舊格式:profiles 直接是設定檔清單,沒有 defaults 可以設 → 原樣輸出、不報錯
        settings = '{\n    "profiles": [ { "guid": "{x}", "name": "cmd" } ]\n}\n'
        self.assertEqual(self.render_terminal_settings(settings), settings)

    # ===============================================================
    # Claude Code 的 settings.json(modify template,#319)
    # ===============================================================
    # 只釘兩個值(跟 Linux 那份 sh + jq 一樣):官方 chrome-devtools plugin 關掉、attribution.commit。
    # 其他(hook、statusLine、autoMode、其他 plugin 開關)是 Claude 和其他工具自己寫的,原樣留著。
    def render_claude_settings(self, existing, source=ROOT):
        """existing(str,None = 檔案不存在)放到 ~/.claude/settings.json,回傳 chezmoi 算出的 bytes。"""
        if existing is None:
            target = self.home / CLAUDE_SETTINGS
            info = {"os": "windows", "homeDir": str(self.home), "kernel": {"osrelease": ""}}
            return subprocess.run([
                "chezmoi", "--no-tty", "--source", str(source), "--config", str(self.cfg),
                "--destination", str(self.home), "--override-data",
                json.dumps({"chezmoi": info, "tools": ["claude"]}), "cat", str(target),
            ], stdin=subprocess.DEVNULL, capture_output=True, check=True).stdout
        return self.cat_bytes(CLAUDE_SETTINGS, existing.encode(), ["claude"], source)

    def test_windows_claude_settings_pins_two_values_and_keeps_the_rest(self):
        existing = {
            "attribution": {"commit": "old", "pr": "Keep PR attribution"},
            "enabledPlugins": {CHROME_PLUGIN: True, "claude-hud@claude-hud": True},
            "hooks": {"SessionStart": [{"hooks": [{"command": "herdr hook", "type": "command"}]}]},
            "statusLine": {"type": "command", "command": "node hud.js"},
            "cleanupPeriodDays": 30,
        }
        first = self.render_claude_settings(json.dumps(existing))
        after = json.loads(first)
        expected = json.loads(json.dumps(existing))
        expected["attribution"]["commit"] = CLAUDE_COMMIT
        expected["enabledPlugins"][CHROME_PLUGIN] = False
        self.assertEqual(after, expected)
        # 第二次 apply 沒有變化
        self.assertEqual(self.render_claude_settings(first.decode()), first)

    def test_windows_claude_settings_keeps_bytes_when_values_already_right(self):
        # Claude 自己改寫過(縮排、key 順序都是它的):值已經對就原樣輸出,chezmoi diff 才是空的
        saved = ('{\n  "theme": "dark",\n  "enabledPlugins": {\n    "%s": false\n  },\n'
                 '  "attribution": {\n    "pr": "",\n    "commit": "%s"\n  }\n}' % (CHROME_PLUGIN, CLAUDE_COMMIT))
        self.assertEqual(self.render_claude_settings(saved).decode(), saved)

    def test_windows_claude_settings_without_file_has_only_pinned_values(self):
        self.assertEqual(json.loads(self.render_claude_settings(None)),
                         {"attribution": {"commit": CLAUDE_COMMIT}, "enabledPlugins": {CHROME_PLUGIN: False}})

    def test_windows_claude_settings_replaces_non_object_values(self):
        # 跟 Linux 的 jq 一樣:attribution 不是物件時整個換成物件
        after = json.loads(self.render_claude_settings('{"attribution": "x", "enabledPlugins": null}'))
        self.assertEqual(after["attribution"], {"commit": CLAUDE_COMMIT})
        self.assertEqual(after["enabledPlugins"], {CHROME_PLUGIN: False})

    def test_windows_claude_settings_has_no_cr_from_crlf_checkout(self):
        crlf = self.crlf_source()
        lf = self.render_claude_settings(None)
        self.assertTrue(lf.endswith(b"}\n") and not lf.endswith(b"\n\n"))
        self.assertEqual(self.render_claude_settings(None, crlf), lf)
        changed = '{"attribution": {"commit": "old"}}'
        self.assertEqual(self.render_claude_settings(changed, crlf),
                         self.render_claude_settings(changed))


if __name__ == "__main__":
    unittest.main()
