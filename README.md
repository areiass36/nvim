# Neovim config

LSP, completion, fuzzy finding, an integrated terminal, debugging (DAP) for .NET, Python,
TypeScript/JavaScript, Vue and React, and a database client for PostgreSQL, MySQL/MariaDB,
SQL Server, SQLite, DuckDB and MongoDB. Everything it needs is installed on first start.

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
| JDK (Temurin 21), used only by the database client | adoptium.net, on the first query (`lua/tools/jdk.lua`) |
| JDBC drivers (PostgreSQL, MySQL, MariaDB, SQL Server, SQLite, DuckDB, MongoDB) | Maven Central, one jar per database, on the first query against it (`lua/tools/jdbc.lua`) |
| tree-sitter-cli | Mason |
| Telescope native sorter (zf) | prebuilt in the plugin |
| Icon font (`ConfigIcons.ttf`) | copied from `assets/fonts` into the user font directory |
| JetBrainsMono Nerd Font Mono | nerd-fonts release, when not installed |
| zig (C compiler for treesitter) | ziglang.org, when no compiler is installed |

Downloads live under `stdpath("data")` (`~/.local/share/nvim` on macOS/Linux,
`%LOCALAPPDATA%\nvim-data` on Windows). Nothing is installed outside of it.

## Checking a new machine

`:Doctor` shows the state of every tool the config installs (ripgrep, netcoredbg, Roslyn, ILSpy,
Mason packages, treesitter parsers, database clients) and of the prerequisites (git, curl, tar, node,
dotnet, python3, C compiler). Start there when something does not work. `:DbDoctor` goes further for
databases and runs `select 1 as a, 2 as b` against every configured connection.

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
lua/db/                  database client: connections, JDBC runner, result grid, schema explorer, diagnostics
java/nvimdb/             the JDBC runner, one process per connection (built on first use)
syntax/tsql.vim          T-SQL highlighting (the treesitter sql parser does not handle it)
tests/db/                headless tests; tests/db/containers.sh starts throwaway servers
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
| `F5` `,dp` | Debug: play the project configuration, or continue a running session |
| `F10` `F11` `F12` | Debug: step over, step into, step out |
| `,dc` | Debug: pick a configuration (the full menu) |
| `,do` `,di` `,dO` | Debug: step over, step into, step out, for terminals where F-keys are taken |
| `,b` `,B` | Breakpoint / conditional breakpoint |
| `,dd` `,du` | Debug: toggle the debug tab (panels) / close it |
| `,ds` `,dk` `,dt` `,dR` | Debug, full screen floats: scopes, stack, program output, REPL |
| `,de` `,dr` | Debug: evaluate the expression under the cursor, inline REPL |
| `,dS` | Debug: pick the active session (compounds have one per app) |
| `,dl` `,dx` | Debug: run the last configuration, terminate every session |
| `,qq` | Run the statement under the cursor (or the selection) |
| `,qc` `,qe` | Pick this buffer's database / explore its schema |
| `,qv` `,qx` | Check the statement on the server without running it / cancel a running query |
| `,qd` | Disconnect (`:DbDisconnect` stops a connection's Java process) |
| `,qn` `,qr` | New query buffer / query the last result with SQL |
| `,qw` `,qC` | Export the result / copy the column under the cursor |

## Debugging (DAP)

`F5` plays the project: with a session running it continues, otherwise it starts the first entry of
`.vscode/launch.json` (its first compound, when there is one) without asking. `,dc` opens the full menu
with every configuration for the filetype. The UI does not open by itself: the code stays clean and `,dd`
switches to a debug tab with scopes, watches, stack, breakpoints, console and REPL. Breakpoints are saved
per project on exit and restored when the file is opened again.

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
  - `Vitest · current file` / `current package`: runs vitest in a single fork
    (`--no-file-parallelism`) and debugs the test in it.
  - Both attach configurations set `restart`, so a `tsx watch`/nodemon reload does not end the session.
- **Vue/React (any front end)**: `Chrome · open dev server` opens Chrome on the dev server URL (suggested
  by probing the usual ports, https first) with source maps; attach to a Chrome started with
  `--remote-debugging-port=9222`.
- **.vscode/launch.json** configurations show up in the menu. `node`/`chrome` become `pwa-node`/`pwa-chrome`,
  `node-terminal` is converted to an equivalent launch, `preLaunchTask` is dropped and flagged in the
  name. A `chrome` launch waits for its URL's port before opening the browser, which is what VS Code does
  with `serverReadyAction`. **Compounds** keep their declaration order, appear with a chain icon and start
  every member as a parallel session; `,dx` ends all.

Example `launch.json` for one play button over a server and a browser. The server configuration runs a
single script that starts every app, so `autoAttachChildProcesses` gives each one its own session, and the
browser member waits for the dev server to listen:

```json
"configurations": [
  { "name": "Full stack", "type": "node", "request": "launch", "runtimeExecutable": "npm", "runtimeArgs": ["run", "dev"], "cwd": "${workspaceFolder}", "console": "integratedTerminal", "autoAttachChildProcesses": true },
  { "name": "Web app in Chrome", "type": "chrome", "request": "launch", "url": "https://localhost:5173", "webRoot": "${workspaceFolder}/apps/web", "sourceMaps": true }
],
"compounds": [ { "name": "Play", "configurations": ["Full stack", "Web app in Chrome"] } ]
```

## Databases

Open a `.sql` file, put the cursor on a statement, press `,qq`. The result appears in a grid below,
one cell at a time under the cursor; `,qe` walks the schema in a Telescope picker. Nothing has to be
installed first.

### How it talks to a database

Everything goes through **JDBC**. The config downloads its own Temurin JDK into
`stdpath("data")/tools/jdk` and uses only that one -- never the `java` on your PATH, so a version
manager with no version selected, or the wrong JDK, cannot break it. The driver for a database is
fetched from Maven Central the first time you query one.

A small Java program (`java/nvimdb/`) is compiled once and runs as **one process per connection**,
kept alive. That is not an optimisation detail: starting a JVM per query was measured at 2.5 s for
DuckDB, which unpacks a native library each time, and 12 s for MongoDB, which boots a JavaScript
engine. Alive, those queries take 1-2 ms and ~110 ms. `:DbDisconnect` stops a connection's process.

Using JDBC is also what makes the rest of this honest:

- **Types come from the driver.** A `numeric` arrives as exact text, an `int8` past 2^53 as text
  (Lua numbers are doubles), a `bytea` as hex -- not as the replacement characters a text protocol
  would leave behind.
- **The catalog is one implementation.** `DatabaseMetaData` replaced six hand-written catalog
  queries against `pg_catalog`, `information_schema`, `sys.objects`, `sqlite_master`,
  `duckdb_tables()` and a Mongo aggregation.
- **Errors carry a SQLState and, from PostgreSQL, the exact character position**, so a diagnostic
  lands on the offending name rather than on the line.
- **Cancelling reaches the server**: `,qx` sends a real JDBC cancel, not a kill.

MongoDB works against a plain `mongod` through JetBrains' Apache-2.0
[mongo-jdbc-driver](https://github.com/DataGrip/mongo-jdbc-driver), the one DataGrip itself uses.
MongoDB's own JDBC driver only speaks to the Atlas SQL interface. A collection has no columns, so
the explorer samples documents and reports each field with its BSON type -- including a field that
holds two types in two documents.

### Connections

Connections are declared in two files, and neither holds a password.

- **Per project**: `.nvim/databases.json` in the repository root. `:DbInit` writes a starter one, and
  refuses to do so until `.nvim/` is gitignored.
- **Globally**: `stdpath("state")/db/connections.json`, same shape, for the databases that are not
  tied to a repository.

```json
{
  "version": 1,
  "default": "local",
  "connections": [
    { "id": "local", "name": "Local", "driver": "postgres", "host": "127.0.0.1", "port": 5432,
      "database": "app_dev", "user": "postgres",
      "password_source": { "kind": "keyring", "account": "local" } },
    { "id": "warehouse", "name": "Warehouse", "driver": "sqlserver", "host": "sql.example.com",
      "database": "DW", "user": "svc_reader", "readonly": true, "production": true },
    { "id": "analytics", "name": "Analytics", "driver": "duckdb", "file": "data/analytics.duckdb" }
  ],
  "bindings": [
    { "glob": "reports/**/*.sql", "connection": "warehouse" },
    { "dir": "db/migrations", "connection": "local" }
  ]
}
```

Drivers: `postgres`, `mysql`, `mariadb`, `sqlserver`, `sqlite`, `duckdb`, `mongodb`. Anything in
`options` is passed to the JDBC driver as it is, which is how you reach a setting this config does
not know about (`"options": { "sslmode": "verify-full", "ApplicationName": "nvim" }`).

Which connection a buffer runs against is decided in this order, and `:DbWhich` says which rule won:
the connection chosen with `,qc` for that buffer, a choice saved for that file, a `glob` or `dir`
binding (the most literal pattern wins), the project `default`, the last connection used in the
project. `readonly` refuses writes before anything is sent, `production` asks first, and an `UPDATE`
or `DELETE` with no `WHERE` asks you to type the connection name.

### Passwords

The password is never written to a file in the clear, and never appears in a command line: the Java
process reads it from the first line of its stdin, so it is not in the JDBC url either. A connection
says where its password comes from:

- `"password_source": { "kind": "keyring", "account": "local" }` -- the OS keyring: Keychain on
  macOS, DPAPI on Windows, `secret-tool` or `pass` on Linux. `:DbSetPassword <id>` stores it,
  `:DbDeletePassword` removes it. When nothing is stored yet you are asked, and offered to keep it.
- `"password_env": "PGPASSWORD"` -- the name of an environment variable, never its value, which is
  the same convention `lua/plugins/lsp/minuet.lua` uses for the API key.
- `"password_command": ["op", "read", "op://vault/db/password"]` -- anything that prints the secret.
- `{ "kind": "prompt" }` -- asked once per session and kept in memory only. `:DbForget` drops it.

A literal `"password"` field in a connection file is an error, not a warning.

### Reading a result

The grid is read-only and shows the value as stored: `NULL` is not an empty string, a `numeric`
keeps its scale, a binary column reads as hex. Columns are measured in display cells, so CJK and
emoji stay aligned, and a long value is truncated on screen but never when yanked or exported.

| Keys | In the result |
|---|---|
| `h` `j` `k` `l` `<Tab>` `<S-Tab>` | Move a cell at a time |
| `y` `Y` `,qC` | Copy the cell, the row (as CSV), the column |
| `s` `S` | Sort by this column, ascending or descending -- re-run on the server, so it covers every page |
| `]p` `[p` | Next and previous page (200 rows by default; the driver caps the rows, no LIMIT is spliced into your SQL) |
| `e` `d` | Export to CSV/JSON; turn this result into a table you can query |
| `<CR>` | The whole document, for MongoDB |
| `q` `<Esc>` | Close |

`d` (or `,qr`) is the DbCode-style part: the page is written as a CSV, registered as a view in a
scratch DuckDB database, and a query buffer opens on it. `SELECT * FROM r1` then works, joins
against another exported result work, and the result of that can be exported in turn. The scratch
lives under `stdpath("state")/db/scratch/<pid>.duckdb` and is deleted when nvim exits; `:DbKeep
<path>` saves a CSV somewhere permanent first. Exporting *everything* streams through the Java side
row by row, so a result far larger than memory still writes.

### Checking a statement before running it

On save, and on `,qv`, the statement under the cursor is checked against the server **without being
executed**: preparing a statement makes the server parse it, resolve the names and describe the
result, and nothing more. One mechanism for every engine -- no `PREPARE` inside a rolled-back
transaction, no `EXPLAIN` that must be kept away from `ANALYZE`, and no SQL Server special case.
(That last one mattered: with the previous command line client, `SET NOEXEC ON` did not survive to
the next statement and a "validated" write ran for real.) A connection marked `production` is left
alone by the automatic pass and checked only when you ask.

Syntax highlighting follows the connection: the treesitter `sql` parser handles ANSI, PostgreSQL,
MySQL, SQLite and DuckDB, with that dialect's own functions, types and keywords drawn on top of it.
T-SQL is the exception -- the parser fails on `[bracketed names]`, `TOP`, `@variables` and `GO` -- so
a SQL Server buffer uses `syntax/tsql.vim` instead.

### Configuration

Anything in `lua/db/config.lua` can be overridden before the plugins load:

```lua
vim.g.db_config = { limit = 500, timeout_ms = 60000, validate_on_save = false }
```

### Tests

```sh
nvim --headless -u tests/minimal.lua -l tests/db/run.lua unit   # no servers needed
tests/db/containers.sh up                                       # throwaway postgres/mysql/mssql/mongo
NVIM_DB_TEST_PW='p@ss:w/rd#1' NVIM_DB_TEST_MSSQL_PW='Str0ng:P/ss#1' \
  nvim --headless -u tests/minimal.lua -l tests/db/run.lua       # everything
tests/db/containers.sh down
```

The live tests skip themselves when nothing is listening. They cover the awkward values (commas,
quotes and newlines inside fields, NULL next to the empty string, CJK, emoji, binary, big integers),
that the password is absent from the process's own command line (checked by pid), and that
validating a `DROP TABLE` leaves the table alone.

## C#: reading .NET source

`gd` on a NuGet symbol opens the source decompiled by Roslyn. For types from .NET and ASP.NET themselves
Roslyn would only show signatures (they come from reference assemblies), so the config decompiles the
whole implementation assembly with ILSpy into a project (`stdpath("data")/tools/ilspy-src`, about 25 s for
`System.Private.CoreLib`, once per runtime version), loads that project into Roslyn and opens the file on
the right overload. Inside the decompiled code hover, `gd` and `gr` work as in any project.
