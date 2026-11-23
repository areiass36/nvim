# Neovim config

LSP, completion, fuzzy finding, an integrated terminal, debugging (DAP) for .NET, Python,
TypeScript/JavaScript, Vue and React, and a database client for PostgreSQL, MySQL/MariaDB,
SQL Server, SQLite, DuckDB, MongoDB and Trino. Everything it needs is installed on first start.

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
| Language servers (Lua, TypeScript, Vue, Angular, JSON, Python, CSS, Java, PowerShell) | Mason |
| C# language server (Roslyn, the one VS Code uses) | `dotnet tool install` into `stdpath("data")/tools/roslyn` |
| ILSpy (`ilspycmd`, decompiles .NET assemblies) | `dotnet tool install`, on the first `gd` into a .NET type |
| Debug adapters: debugpy (Python), js-debug (Node/Chrome) | Mason |
| Debug adapter: netcoredbg (.NET) | GitHub release (`lua/tools/netcoredbg.lua`) |
| ripgrep (Telescope live grep) | GitHub release (`lua/tools/ripgrep.lua`) |
| JDK (Temurin 21), used only by the database client | adoptium.net, on the first query (`lua/tools/jdk.lua`) |
| JDBC drivers (PostgreSQL, MySQL, MariaDB, SQL Server, SQLite, DuckDB, MongoDB, Trino) | Maven Central, one jar per database, on the first query against it (`lua/tools/jdbc.lua`) |
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
- **pwsh**: the PowerShell server runs inside a shell, and PowerShell 7 is the one it is started in.
  Windows only ships 5.1 (`powershell.exe`); that one is used instead when `pwsh` is not installed.
- **JDK 25 or newer**: the Java server (jdtls), which refuses to start on anything older. Taken from
  `JAVA_HOME`, or from the `java` on PATH; a version manager is fine (`mise use -g java@25`). The JDK in
  the table above is the database client's and is not used for this.

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
  profile and adds a Special Exception for U+F600-U+F62A. Select it in Settings > Profiles (or make it the
  default). Manual alternative: Profiles > Text > enable "Use a different font for non-ASCII text" with the
  same font, then Manage Special Exceptions > add the range with font `ConfigIcons`.
- **Windows Terminal**: done automatically (`profiles.defaults.font.face = "JetBrainsMono NFM, ConfigIcons"`).
- **kitty**: `symbol_map U+F600-U+F62A ConfigIcons`.
- **WezTerm**: `font = wezterm.font_with_fallback({ "JetBrainsMono NFM", "ConfigIcons" })`.

To add or change an icon, edit `assets/icons/map.json` and `lua/core/icons.lua` together, rebuild the font
(`scripts/icon-font/README.md`, which needs the Font Awesome Pro package), commit the TTF with them, and
restart the terminal so it picks the new file up.

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
lua/debugger/            dap-ui behaviour, adapters per language, keymaps
lua/runner/              workspace runner: reads .nvim/workspace.json, starts runners and clusters
lua/grip/                the database explorer: the Telescope picker, its preview pane, and the vocabulary they share
lua/plugins/db/          neogrip.nvim spec -> the database client, plus every ,q keymap
lua/db/                  the client this config grew, now published as neogrip.nvim; nothing loads it any more
java/nvimdb/             its JDBC runner, likewise published; tests/db/ is what still reads both
syntax/tsql.vim          T-SQL highlighting (the treesitter sql parser does not handle it)
tests/grip/              headless tests for the explorer: a fixture catalog on disk, no server anywhere
tests/db/                headless tests; tests/db/containers.sh starts throwaway servers
tests/runner/            headless tests for the workspace runner
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
| `,rc` `,rp` | Runner: validate the project's `.nvim/workspace.json` / show the plan |
| `,rr` `,ra` `,rs` | Runner: start the default target / an address / stop the processes |
| `F5` | Debug: continue a running session, or pick a configuration |
| `F10` `F11` `F12` | Debug: step over, step into, step out |
| `,dc` | Debug: pick a configuration (the full menu) |
| `,do` `,di` `,dO` | Debug: step over, step into, step out, for terminals where F-keys are taken |
| `,b` `,B` | Breakpoint / conditional breakpoint |
| `,dd` `,du` | Debug: toggle the debug tab (cursor on the variables) / close it |
| `,dt` | Debug: program output, full screen like `,t` |
| `,ds` `,dw` `,dk` `,dR` | Debug, focused floats: variables, watches, stack, REPL |
| `,de` `,dr` | Debug: evaluate the expression under the cursor, inline REPL |
| `,dS` | Debug: pick the active session (compounds have one per app) |
| `,dl` `,dx` | Debug: run the last configuration, terminate every session |
| `,qq` | Run the statement under the cursor (or the selection) |
| `,qc` `,qe` | Pick this buffer's database / explore its schema |
| `,qi` | Read the whole catalog into a snapshot (`:DbIntrospect`) |
| `,qv` `,qx` | Check the statement on the server without running it / cancel a running query |
| `,qd` | Disconnect (`:DbDisconnect` stops a connection's Java process) |
| `,qn` `,qr` | New query buffer / query the last result with SQL |
| `,qw` `,qC` | Export the result / copy the column under the cursor |

## Start screen

`nvim` on its own draws the dashboard: the logo, the working directory with its branch and the Neovim
version, the project pickers above the divider and the config's own tooling below it.

`nvim .` (or `nvim some/dir`) does not land in netrw. The directory becomes the working directory, so the
pickers and the language servers root themselves there, and the Telescope file browser opens on it with
the dashboard drawn behind: closing the browser leaves you on the start screen instead of in a directory
listing.

## Debugging (DAP)

`F5` continues a running session and opens the configuration menu when there is none; `,dc` is that same
menu. What a project runs is declared in its own `.nvim/workspace.json` (see Runner below), so the
configurations here are the fallback for a project without one. The UI does not open by itself: the code
stays clean and `,dd`
switches to a debug tab with scopes, watches, stack, breakpoints, console and REPL, with the cursor on the
variables. Breakpoints are saved per project on exit and restored when the file is opened again.

Every window opens focused, in one of the two shapes this config already uses: `,dt` shows the program
output the way `,t` shows a terminal — the whole screen, no border — and `,ds` `,dw` `,dk` `,dR` show
variables, watches, stack and REPL in a wide rounded float. `q` and `Esc` close them (`Esc` also from
terminal mode), and a stop closes them so the line the program stopped on is not left behind a float.
nvim-dap-ui's own `float_element` is not used for this: it anchors the window at the cursor, shrinks it to
the content and closes an unfocused float on the next cursor move.

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
- **.vscode/launch.json is not read.** Every entry in a real one tends to hang off `preLaunchTask`, which
  nvim-dap cannot run, so the task was silently dropped and `F5` would start whatever happened to be first
  — on this machine, a macOS-only simulator script. The file stays in the repository for VS Code; the
  provider is off (`dap.providers.configs["dap.launch.json"] = nil` in `lua/debugger/init.lua`).

## Runner (workspace.json)

What a project runs lives in `.nvim/workspace.json` at the root of the project: `project[] -> runner[]`
plus `cluster[]` to start several at once, and `link[]` so one workspace can compose runners declared in
another. The format is atomic on purpose — no `extends`, no `include`, no per-cluster overrides, and the
runner never writes to the file. `,rc` (`:RunnerCheck`) validates the file above the current buffer and
reports every problem with its path, like `project[2].runner[1].command`.

```json
{
  "version": 1,
  "workspace": "mark",
  "default": { "cluster": "local" },
  "project": [
    {
      "name": "api",
      "path": "apps/api",
      "runner": [
        {
          "label": "main",
          "command": ["npm", "run", "dev"],
          "env": { "PORT": "3000" },
          "ready": { "port": 3000 },
          "debug": { "adapter": "pwa-node", "autoAttachChildProcesses": true },
          "singleton": true
        }
      ]
    }
  ],
  "cluster": [{ "name": "local", "member": [{ "project": "api", "runner": "main" }] }]
}
```

`exclude` hides files from `<leader>ff`, `<leader>fg` and the file browser (`<leader>ee`, `<leader>ef`),
including the preview of a folder, the way `files.exclude` does in VS Code. Each entry is a glob relative to the workspace root, read the
gitignore way: a name without a slash (`dist`, `*.min.js`) matches at any depth, one with a slash
(`apps/legacy`, `apps/*/dist`) only from the root, and hiding a folder hides everything inside it. The
list is read again on every search and on every listing of the browser, so an edit applies on the next
one with nothing to reload, and it is read even when the rest of the file has errors. `<leader>ff` and
`<leader>fg` take the workspace above the cwd, where rg searches; the browser takes the one above the
folder it is showing.

```json
{ "exclude": ["dist", "coverage", "**/*.min.js", "apps/legacy/**"] }
```

The file is found by walking up from the buffer, never from the cwd. `,rr` (`:RunnerRun`) starts the
default target and `:RunnerRun <address>` a specific one, completing on `project:label` and `#cluster`:
each wave is started together and waited for (`ready`: `port`, `http`, `log`, `delay`) before the next
one begins. A runner with `debug` goes to nvim-dap instead of jobstart — on `launch` the adapter owns the
process and `command` becomes the debuggee (for `python` the first word is the interpreter, so it lands in
`pythonPath`); on `attach` the `command` is treated as a tunnel, started first, and the session connects
once `ready` fires. Every other field of `debug` is passed to the adapter untouched (`pathMappings`,
`justMyCode`, ...). `,rs` (`:RunnerStop`) stops the processes it started; debug sessions stay with the
debugger (`,dx`). Still missing: `${input:...}` has no prompt yet, `cluster.stopTogether` is not honoured
by the stop, and `oneShot` is declarative only.

```sh
nvim --headless -u tests/minimal.lua -l tests/runner/run.lua unit   # schema, addressing, dap bridge
nvim --headless -u tests/minimal.lua -l tests/debugger/run.lua      # shape and focus of the debug windows
```

## Databases

Open a `.sql` file, put the cursor on a statement, press `,qq`. The result appears in a grid below,
one cell at a time under the cursor; `,qe` walks the schema of the database the buffer runs against
in a Telescope picker. Nothing has to be installed first.

### Walking the schema

neogrip answers the catalog as data and ships no explorer of its own, so the one the editor shows is
this config's: `lua/grip/`, built on the same Telescope the file browser uses and shaped like it,
because a database is a tree you browse and this editor already has a way of browsing trees.

`,qe` opens on the database the buffer runs against -- the connection `:NGripWhich` reports, resolved
by the same rules -- and steps through its schemas, tables and columns in one picker that is
refreshed in place rather than reopened. The list of every configured connection is one level
*above* that, so it is there when you want it and never in the way when you do not; a buffer with no
database bound to it opens on the list instead.

Every level below the first opens with a `..` row at the top, which walks back out -- the same row
the file browser puts at the top of a directory, because a way back you have to remember is a way
back you do not use. The cursor deliberately starts on the row *below* it, so confirming the first
thing you see never bounces you out of the level you just entered, and the row disappears as soon as
you type a letter: while you are filtering you want tables, not the way out. `<BS>` on an empty
prompt does the same thing, and does nothing at the connection list, which is the top of the tree.

Each row says what is already known about it, and never spends a round trip to find out: a
connection reports its driver and where it points, a table its column count and its remark, a column
its type with `PK` and `NOT NULL`, and a view says that it is one.

The picker brings no geometry of its own and takes the full-window horizontal layout with a
half-width preview that `lua/plugins/editor/telescope.lua` gives every picker in this config. It
overrides exactly one thing: Telescope hides a preview below 120 columns, and here the pane is half
the point, so it stays at any width. Otherwise the rule holds -- a picker declares what it lists,
never how large it is.

Which level you are on is legible from the icons rather than from the title: a server for a
connection, a database, a stack of layers for a schema, a sheet of rows for a table, an eye for a
view, braces for a MongoDB collection, a sheet of columns for a column -- and a key for a column
that is part of the primary key.

The pane beside the list says what the row under the cursor holds. A connection: which engine, where
it points, who it logs in as, whether its process is up, what has been swept out of it and when,
then its databases or schemas. A schema: its tables and views with their column counts. A column:
its type, whether it takes a null, whether it is the key, its default and its remark. A table: the
same rendered `CREATE TABLE` that `<CR>` opens, highlighted as SQL, so what you read beside the list
and what you read after pressing `<CR>` cannot disagree about a column -- followed by the engine's
own row estimate where it keeps one cheaply (PostgreSQL, MySQL, MariaDB, SQL Server; the others
answer nothing rather than counting rows for you), and then ten real rows of the table.

Those ten rows are a `SELECT` against the table the cursor is on, so they are not taken from a
connection marked `production`: a replica that serves an application is the wrong place to spend a
query per keystroke. There the pane says so and `<C-l>` samples it when you ask for it.
`require("grip.preview").options` is where the ten, the debounce and the whole sample live.

| | |
| --- | --- |
| `<CR>` | walk in; on a table open its definition; on a column insert its name |
| `<BS>` | walk back out (in insert mode, on an empty prompt) |
| `<C-o>` | walk in anyway -- a table's columns, where `<CR>` stops |
| `<C-s>` | a `SELECT` for this table in a query buffer |
| `<C-g>` | pick the statement to write: `SELECT`, `INSERT`, `UPDATE`, `DELETE` |
| `<C-y>` | insert the qualified name where the explorer was opened from |
| `<C-d>` | open it as a document: a table's definition, a schema's listing |
| `<C-l>` | sample this table's rows into the pane |
| `<C-r>` | forget the cached catalog, re-read it, and sweep it again |

Walking into a database on PostgreSQL or SQL Server opens a connection of its own, because neither
engine can query across databases and JDBC answers nothing about the schemas of one you are not
connected to. The derived connection is registered for the session -- the id it came from plus the
database's name -- and the walk goes on from its own server row. Trino needs none of that: one
session queries every catalog, so picking one there only changes the names a statement is written
with.

`<C-g>` writes a statement for the table under the cursor -- a `SELECT`, or an `INSERT`, `UPDATE` or
`DELETE` built from the catalog. The columns the server writes itself (identity and generated ones)
are left out of an `INSERT`, and an `UPDATE` or `DELETE` arrives with its primary key already in the
`WHERE`; a table with no key reported says so in a comment and leaves the condition empty rather
than inventing one, because an unqualified `UPDATE` rewrites every row. The values are named
placeholders, so nothing in the buffer looks runnable until you have finished it.

`<CR>` on a table stops the walk and opens that definition in a read-only `sql` buffer, and it is
SQL you could run: a `CREATE TABLE` with named `CONSTRAINT` clauses, composite keys in the order the
server reports them, `ON DELETE CASCADE` where there is one, identity and generated columns marked;
then the indexes as `CREATE INDEX` statements rather than notes about them, with a column's `DESC`
and a partial index's `WHERE` kept; then `COMMENT ON` for whatever the server had remarks for. The
index that merely implements a declared key is left out, because the constraint above already says
it. Only the tables that reference *this* one stay comments -- they are not this table's DDL.

What `DatabaseMetaData` cannot describe at all is a check constraint, so where one statement gets
the server's own text -- `SHOW CREATE TABLE` on MySQL, MariaDB and Trino, `sqlite_master` on SQLite,
`pg_get_constraintdef` and the index definitions on PostgreSQL -- it is appended under
the heading `-- As the server writes it`. An engine without one does not get that section, and a
query engine such as Trino, which reports no indexes or keys at all, says so rather than leaving
the sections out.

The definition replaces the current window's buffer the way `:edit` would, instead of splitting: the
window count does not grow by one for every table you look at, `<C-^>` and `#` go back to the query
you came from, and `q` returns to the previous buffer rather than closing the window. A window
already showing that table is reused. `<C-o>` steps into the column list instead.

Without a snapshot of the catalog -- the next section -- entering a schema costs **one** round trip:
`getColumns` takes a table pattern, so a single sweep brings back every table with every column, and
the levels under it and the preview beside it are then answered from the cache. Resting on a schema
warms it in the background, so walking in is usually instant.

### Introspecting a database once

`:DbIntrospect` (`,qi`) sweeps the connected database in one pass -- every schema, table, column,
primary key, index and foreign key of it -- and writes what it finds as a snapshot under
`stdpath("state")/db/catalog/`. Every level of the explorer and every table preview is answered from
that file afterwards, with no round trip at all: across editor restarts, and with the database
unreachable.

The snapshot has no TTL, deliberately. It is replaced when you run `:DbIntrospect` again, dropped by
`:DbSchemaReload` along with the cached catalog, and left alone otherwise, so that walking the tree
never silently pays for a refresh of something you were only reading. `:DbDoctor` prints how old a
connection's snapshot is and how many schemas, tables and columns it holds, which is what tells you
whether to take another.

The sweep runs on JDBC connections of its own, several at a time, and off the single worker thread
the connection answers queries on -- so a query typed while it is running is not queued behind it.
Where a second connection cannot be opened, and on the drivers that take one writer at a time
(SQLite, DuckDB) and on MongoDB, it falls back to that one connection and sweeps sequentially.

Opening the explorer on a database with no snapshot starts one in the background and goes on
answering a schema at a time meanwhile, so the first walk is never the one that waits for it.

### How it talks to a database

Everything goes through **JDBC**. The config downloads its own Temurin JDK into
`stdpath("data")/tools/jdk` and uses only that one -- never the `java` on your PATH, so a version
manager with no version selected, or the wrong JDK, cannot break it. The driver for a database is
fetched from Maven Central the first time you query one.

A small Java program (`java/nvimdb/`) is compiled once and runs as **one process per connection**,
kept alive. That is not an optimisation detail: starting a JVM per query was measured at 2.5 s for
DuckDB, which unpacks a native library each time, and 12 s for MongoDB, which boots a JavaScript
engine. Alive, the same queries take milliseconds, and MongoDB's first a fraction of a second
instead of twelve of them. `:DbDisconnect` stops a connection's process.

Using JDBC is also what makes the rest of this honest:

- **Types come from the driver.** A `numeric` arrives as exact text, an `int8` past 2^53 as text
  (Lua numbers are doubles), a `bytea` as hex -- not as the replacement characters a text protocol
  would leave behind.
- **The catalog is one implementation.** `DatabaseMetaData` replaced six hand-written catalog
  queries against `pg_catalog`, `information_schema`, `sys.objects`, `sqlite_master`,
  `duckdb_tables()` and a Mongo aggregation.
- **A table's indexes and the keys pointing at it are the driver's answer too**, which is what the
  definition buffer is written from (`getIndexInfo`, `getImportedKeys`, `getExportedKeys`).
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

- **Per project**: `.nvim/databases.json`. It is looked for from the working directory upwards, and
  the nearest one decides what the project *is* -- above a `.git`, if that is where it sits. A folder
  holding several repositories side by side can therefore declare its databases once, at the top, and
  they resolve from inside any of them. `:DbInit` writes a starter file next to the git root, or in
  the working directory when there is none, and in a repository refuses until `.nvim/` is gitignored.
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

Drivers: `postgres`, `mysql`, `mariadb`, `mssql`, `sqlite`, `duckdb`, `mongodb`, `trino` -- which
is what `:DbConnections` prints. `postgresql`, `pg`, `sqlserver`, `tsql`, `sqlite3`, `mongo` and
`presto` are accepted as aliases for them.
Anything in `options` is passed to the JDBC driver as it is, which is how you reach a setting this
config does not know about (`"options": { "sslmode": "verify-full", "ApplicationName": "nvim" }`).

**Trino** has one level more than the others: a catalog above the schema. `database` names the
catalog, `default_schema` the schema inside it, and both are optional -- with neither, a query names
them itself (`catalog.schema.table`) and `,qe` starts at the list of catalogs. Port 443 turns `SSL`
on by itself; a gateway with a certificate the machine does not trust needs
`"options": { "SSLVerification": "NONE" }`.

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
| `0` `$` `gg` `G` | First and last column, first and last row |
| `y` `Y` `,qC` | Copy the cell, the row (as CSV), the column |
| `s` `S` | Sort by this column, ascending or descending -- re-run on the server, so it covers every page |
| `]p` `[p` | Next and previous page (200 rows by default; the driver caps the rows, no LIMIT is spliced into your SQL) |
| `gf` | Follow the foreign key under the cursor to the row it points at |
| `e` `d` | Export to CSV/JSON; turn this result into a table you can query |
| `<CR>` | The whole document, for MongoDB |
| `q` `<Esc>` | Close |

`gf` is the one that changes how it feels to read data. The driver reports which table each result
column came from, and the swept catalog knows that table's foreign keys, so on a `customer_id` the
grid can write the `SELECT` for the customer it refers to -- the whole key at once when it has
several columns, and from the stored value, not the one on screen. A column that is not part of a
key, a `NULL` cell, a table the sweep has not reached: each says so and does nothing, rather than
generating a statement that would mean something else.

A statement that changed rows no longer opens an empty table. The footer reads `3 rows affected` --
or `statement ran`, for a driver that will not say how many.

A value is coloured by what it holds -- a number, a date, a boolean, `NULL`, a uuid, JSON -- in the
colour the colourscheme already gives that kind of literal, so a result reads like the rest of the
editor. Text keeps the plain foreground, because it is most of a result and it is what you are
reading; the rule and the `│` between columns drop back to the colour of a window separator. Every
other row is tinted like the cursor line (`stripe_rows = false` turns that off), the column the rows
are ordered by is underlined in the header, and in the footer a slow query's time and a
`production` connection's name are called out. Each group can be overridden, and is re-applied when
the colourscheme changes:

| Group | What it paints |
|---|---|
| `DbGridHeader` `DbGridHeaderSorted` | The column names, and the one the rows are ordered by |
| `DbGridRule` `DbGridSeparator` `DbGridStripe` | The rule, the `│` between columns, every other row |
| `DbGridNumber` `DbGridBoolean` `DbGridTemporal` | A number, a boolean, a date, time or timestamp |
| `DbGridUuid` `DbGridJson` `DbGridNull` `DbGridBinary` | A uuid, JSON, `NULL`, bytes that were never text |
| `DbGridEllipsis` `DbGridCell` | The `…` of a truncated value, the cell under the cursor |
| `DbGridFooter` `DbGridConnection` `DbGridProduction` `DbGridCount` `DbGridElapsed` `DbGridSlow` | The line under the table |

```lua
vim.api.nvim_set_hl(0, "DbGridNumber", { fg = "#b5cea8" })
```

`d` (or `,qr`) is the DbCode-style part: the page is written as a CSV, registered as a view in a
scratch DuckDB database, and a query buffer opens on it. `SELECT * FROM r1` then works, joins
against another exported result work, and the result of that can be exported in turn. The scratch
lives under `stdpath("state")/db/scratch/<pid>.duckdb` and is deleted when nvim exits. `:DbKeep
<path>` writes the result page you are looking at to a CSV of your own, outside the directory that
gets collected. Exporting *everything* streams through the Java side
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
MySQL, SQLite, DuckDB and Trino, with that dialect's own functions, types and keywords drawn on top
of it.
T-SQL is the exception -- the parser fails on `[bracketed names]`, `TOP`, `@variables` and `GO` -- so
a SQL Server buffer uses `syntax/tsql.vim` instead.

### Going to a definition

`gd` on a table name in a query buffer opens that table's definition. `K` summarises it without
leaving the statement, `gr` lists the tables it is tied to by a foreign key, `gO` outlines the
statements in the file, and the workspace-symbol picker finds any table, view or column in the
database by name.

They work because the database client *is* a language server -- a small one, written in Lua and run
in this process, started on a buffer the moment a connection resolves for it. There is no binary to
install and nothing for Mason to manage. It answers from the swept catalog on disk, so a jump costs
nothing and works with the server unreachable; a table nobody has swept yet is still answered, from
one round trip.

Definitions are documents, not files: `db://table/<connection>/<catalog>/<schema>/<table>` and
`db://schema/...` render on demand, which is why `<C-^>` and the jumplist behave normally and why
`gd` on a column lands on that column's line inside the table's definition rather than at the top of
it. An alias is resolved within the statement under the cursor -- `select o.total from orders o`
jumps from `o.total` to `total` in `orders` -- and a name inside a string or a comment resolves to
nothing, which is the difference between a resolver and a search.

The server deliberately does not offer completion, which the cmp source already does, and
deliberately does not emit semantic tokens, which at their priority would paint over the dialect
highlighting described above.

### Configuration

Anything in `lua/db/config.lua` can be overridden before the plugins load:

```lua
vim.g.db_config = { limit = 500, timeout_ms = 60000, validate_on_save = false }
```

The sweep has three keys of its own: `introspect_parallelism` (4) connections at once,
`introspect_timeout_ms` (600000) for the whole pass, and `introspect_details` (true) to collect each
table's indexes and foreign keys as well, which is what lets a definition be previewed without
asking the server. Sweeping a database the first time the explorer reaches one that has never been
swept is the explorer's own doing, not the client's: `lua/grip/explorer.lua` starts it in the
background and waits for nothing, so the levels keep being served a round trip at a time until it
lands.

### Tests

```sh
nvim --headless -u tests/minimal.lua -l tests/grip/run.lua      # the explorer: picker, pane, walk
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
