# Neovim config

LSP, completion, fuzzy finding, an integrated terminal and debugging (DAP) for .NET, Python,
TypeScript/JavaScript, Vue and React. Everything it needs is installed on first start.

## Install

Only **Neovim 0.11+** and **git** are required:

```sh
git clone https://github.com/areiass36/nvim ~/.config/nvim        # macOS / Linux
git clone https://github.com/areiass36/nvim %LOCALAPPDATA%\nvim    # Windows
nvim
```

On the first start the config downloads what it needs:

| What | How |
|---|---|
| Plugins | lazy.nvim |
| Language servers (Lua, TypeScript, Vue, Angular, JSON, Python, CSS) | Mason |
| C# language server (Roslyn, the one VS Code uses) | `dotnet tool install` into `stdpath("data")/tools/roslyn` |
| ILSpy (`ilspycmd`, decompiles .NET assemblies) | `dotnet tool install`, on the first `gd` into a .NET type |
| Debug adapters: debugpy (Python), js-debug (Node/Chrome) | Mason |
| Debug adapter: netcoredbg (.NET) | GitHub release (`lua/tools/netcoredbg.lua`) |
| ripgrep (Telescope live grep) | GitHub release (`lua/tools/ripgrep.lua`) |
| tree-sitter-cli | Mason |
| Telescope native sorter (zf) | prebuilt in the plugin |
| Icon font (`ConfigIcons.ttf`) | copied from `assets/fonts` into the user font directory |
| JetBrainsMono Nerd Font Mono | nerd-fonts release, when not installed |
| zig (C compiler for treesitter) | ziglang.org, when no compiler is installed |

Downloads live under `stdpath("data")` (`~/.local/share/nvim` on macOS/Linux,
`%LOCALAPPDATA%\nvim-data` on Windows). Nothing is installed outside of it.

## Checking a new machine

`:Doctor` shows the state of every tool the config installs (ripgrep, netcoredbg, Roslyn, ILSpy,
Mason packages, treesitter parsers) and of the prerequisites (git, curl, tar, node, dotnet, python3,
C compiler). Start there when something does not work.

### Windows

Nothing to do by hand. Install Neovim and git (`winget install Neovim.Neovim Git.Git`), clone into
`%LOCALAPPDATA%\nvim` and open `nvim`. On the first start the config also:

- downloads **JetBrainsMono Nerd Font Mono** and the icon font, installs them for the current user and
  registers them in the registry (`HKCU\...\Fonts`);
- sets Windows Terminal's default font to `JetBrainsMono NFM, ConfigIcons` (the comma list is the font
  fallback); a backup of `settings.json` is kept next to it;
- downloads a portable **zig** and uses it as the C compiler (`CC=zig cc`) for treesitter parsers when no
  compiler is installed.

Restart Windows Terminal once after the first start so it picks up the new fonts. `curl` and `tar` ship with
Windows 10/11. Attaching the debugger to node processes uses js-debug's attach-by-pid (there is no `SIGUSR1`).
Everything was validated on macOS; on Windows run `:Doctor` first if something looks off.

## Language toolchains

The config does not install languages. Have on PATH what you use:

- **node / npm**: TypeScript, Vue, Angular, CSS and JSON servers, js-debug (Mason needs it to install them).
- **dotnet SDK**: C# (Roslyn) and .NET debugging. If `dotnet` comes from a version manager (asdf, mise),
  `DOTNET_ROOT` must be exported in the shell.
- **python3**: pyright and debugpy.

### C compiler

Treesitter highlighting requires compiling parsers. With `cc`/`gcc`/`clang`/`zig`/`cl` on PATH they are
built with it; otherwise the config downloads a portable zig into `stdpath("data")/tools/zig` and uses
`zig cc`. macOS has a compiler once the Xcode Command Line Tools are installed (they come with git).

## Icon font

Every icon in the UI (diagnostics, breakpoints, dashboard, statusline, file and folder icons in Telescope
and in the LSP pickers) comes from `assets/fonts/ConfigIcons.ttf`, an icon-only font built from Font
Awesome SVGs (`assets/icons/`, see `scripts/icon-font/`). Each icon is used in exactly one context;
`lua/core/icons.lua` is the single place that maps names to glyphs (U+F600 onwards, a private-use range
the Nerd Fonts leave empty).

On startup the config copies the font into your font directory. The terminal must then be told to use it
for that range; operating systems do not fall back to arbitrary fonts for private-use code points.

- **iTerm2 (macOS)**: the config writes a Dynamic Profile named `ConfigIcons` that inherits your default
  profile and adds a Special Exception for U+F600-U+F620. Select it in Settings > Profiles (or make it the
  default). Manual alternative: Profiles > Text > enable "Use a different font for non-ASCII text" with the
  same font, then Manage Special Exceptions > add the range with font `ConfigIcons`.
- **Windows Terminal**: done automatically (`profiles.defaults.font.face = "JetBrainsMono NFM, ConfigIcons"`).
- **kitty**: `symbol_map U+F600-U+F620 ConfigIcons`.
- **WezTerm**: `font = wezterm.font_with_fallback({ "JetBrainsMono NFM", "ConfigIcons" })`.

To change an icon, replace the SVG in `assets/icons/` (keep the file name), run the build script, and
restart the terminal.

## Layout

```
init.lua                 -> require("core")
lua/core/                options, editor keymaps, autocmds, lazy.nvim bootstrap, platform facts, icons
lua/tools/               binaries the config installs: ripgrep, netcoredbg, dotnet tools, Mason, fonts, zig, terminal setup, :Doctor
lua/plugins/ui/          colorscheme, lualine, dashboard, devicons (one generic file icon)
lua/plugins/editor/      telescope, harpoon, toggleterm, treesitter, unception
lua/plugins/lsp/         nvim-lspconfig (+ keymaps), completion, mason, actions-preview
lua/plugins/dap/         nvim-dap spec -> lua/debugger
lua/servers/             one file per language server (vim.lsp.config)
lua/csharp/              gd into decompiled .NET sources (metadata parsing, ILSpy projects)
lua/debugger/            dap-ui behaviour, adapters per language, launch.json support, keymaps
```

Each plugin spec defines its own keymaps; editor-wide ones are in `lua/core/keymaps.lua`.

## Keymaps

Leader is `,`.

| Keys | Action |
|---|---|
| `,ff` `,fg` `,fb` `,fr` | Telescope: files, live grep, buffers, recent files |
| `,ee` `,ef` | File browser (project root / current file folder) |
| `,a` `,es` | Harpoon: add / list |
| `,t` | Terminals (toggleterm manager) |
| `gd` `gr` `gi` `go` `gh` `gs` | LSP: definition, references, implementation, type, hover, signature |
| `ga` `rn` `,s` | Code actions, rename, diagnostics float |
| `F5` `F10` `F11` `F12` | Debug: continue, step over, step into, step out |
| `,dc` `,do` `,di` `,dO` | Debug: the same, for terminals where F-keys are taken |
| `,b` `,B` | Breakpoint / conditional breakpoint |
| `,dd` `,du` | Debug: toggle the debug tab (panels) / close it |
| `,ds` `,dk` `,dt` `,dR` | Debug, full screen floats: scopes, stack, program output, REPL |
| `,de` `,dr` | Debug: evaluate the expression under the cursor, inline REPL |
| `,dS` | Debug: pick the active session (compounds have one per app) |
| `,dl` `,dx` | Debug: run the last configuration, terminate every session |

## Debugging (DAP)

`F5` in a file lists the configurations for its filetype. The UI does not open by itself: the code stays
clean and `,dd` switches to a debug tab with scopes, watches, stack, breakpoints, console and REPL.

- **C#**: `.NET · build + launch` runs `dotnet build`, launches the project's apphost (asks which one when
  there are several) with the `DOTNET_ROOT` of the target runtime; `.NET · attach to process`. netcoredbg
  has no integrated terminal, so program output is rendered into a terminal emulator attached to the
  console panel (colors preserved).
- **Python**: current file (uses the project's `.venv`/`venv` when present); attach to debugpy on 5678.
- **JS/TS**:
  - `Node · npm run <script>`: runs an npm script (dev scripts first) in the folder of the closest
    `package.json` and attaches to child processes (tsx watch, nodemon, vite). This is how you debug a server.
  - `Node · attach (running process)`: pick the node process and attach, even without `--inspect`
    (sends `SIGUSR1`; Windows uses js-debug's attach-by-pid).
  - `Node · attach on port 9229`: for processes started with `--inspect`.
  - `Node · current file` / `with tsx`: standalone scripts.
- **Vue/React (any front end)**: `Chrome · open dev server` opens Chrome on the dev server URL (suggested
  by probing the usual ports, https first) with source maps; attach to a Chrome started with
  `--remote-debugging-port=9222`.
- **.vscode/launch.json** configurations show up in the menu. `node`/`chrome` become `pwa-node`/`pwa-chrome`,
  `node-terminal` is converted to an equivalent launch, `preLaunchTask` is dropped and flagged in the
  name. **Compounds** appear with a chain icon and start every member as a parallel session; `,dx` ends all.

Example `launch.json` to start an API and a web app together:

```json
"configurations": [
  { "name": "API (dev)", "type": "node", "request": "launch", "runtimeExecutable": "npm", "runtimeArgs": ["run", "dev"], "cwd": "${workspaceFolder}/apps/api", "console": "integratedTerminal", "autoAttachChildProcesses": true },
  { "name": "Web (dev)", "type": "node", "request": "launch", "runtimeExecutable": "npm", "runtimeArgs": ["run", "dev"], "cwd": "${workspaceFolder}/apps/web", "console": "integratedTerminal", "autoAttachChildProcesses": true }
],
"compounds": [ { "name": "API + Web (dev)", "configurations": ["API (dev)", "Web (dev)"] } ]
```

## C#: reading .NET source

`gd` on a NuGet symbol opens the source decompiled by Roslyn. For types from .NET and ASP.NET themselves
Roslyn would only show signatures (they come from reference assemblies), so the config decompiles the
whole implementation assembly with ILSpy into a project (`stdpath("data")/tools/ilspy-src`, about 25 s for
`System.Private.CoreLib`, once per runtime version), loads that project into Roslyn and opens the file on
the right overload. Inside the decompiled code hover, `gd` and `gr` work as in any project.
