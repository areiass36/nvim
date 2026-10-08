-- Every icon the UI renders, in one place. The glyphs live in the icon-only
-- font assets/fonts/ConfigIcons.ttf (built from assets/icons/*.svg by
-- scripts/icon-font/build.mjs) at U+F600 onwards, a private-use range the
-- Nerd Fonts leave empty. Each icon is used in exactly one context.
return {
	diagnostic_error = "\u{f600}", -- circle-xmark
	diagnostic_warn = "\u{f601}", -- triangle-exclamation
	diagnostic_info = "\u{f602}", -- circle-info
	diagnostic_hint = "\u{f603}", -- lightbulb
	breakpoint = "\u{f604}", -- circle-dot
	breakpoint_condition = "\u{f605}", -- circle-question
	breakpoint_rejected = "\u{f606}", -- ban
	stopped = "\u{f607}", -- arrow-right
	dotnet = "\u{f608}", -- hashtag
	node = "\u{f609}", -- circle-nodes
	python = "\u{f60a}", -- code
	chrome = "\u{f60b}", -- globe
	compound = "\u{f60c}", -- link
	find_file = "\u{f60d}", -- magnifying-glass
	live_grep = "\u{f60e}", -- binoculars
	recent_files = "\u{f60f}", -- clock-rotate-left
	browse = "\u{f610}", -- folder-open
	settings = "\u{f611}", -- gear
	mason = "\u{f612}", -- toolbox
	lazy = "\u{f613}", -- plug
	quit = "\u{f614}", -- power-off
	bolt = "\u{f615}", -- bolt
	modified = "\u{f616}", -- pen
	readonly = "\u{f617}", -- lock
	file = "\u{f618}", -- file
	folder = "\u{f619}", -- folder
	check = "\u{f61a}", -- check
	cross = "\u{f61b}", -- xmark
	terminal = "\u{f61c}", -- terminal
	chevron_right = "\u{f61d}", -- chevron-right
	chevron_down = "\u{f61e}", -- chevron-down
	current_frame = "\u{f61f}", -- angles-right
	branch = "\u{f620}", -- code-branch
}
