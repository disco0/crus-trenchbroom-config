const MOD_DPRINT_BASE = 'tb-config:resolver'
func dprint(msg: String, ctx: String = "") -> void:
	if Engine.editor_hint:
		print("[%s] %s" % [ MOD_DPRINT_BASE + (":" + ctx if len(ctx) > 0 else ""), msg])
	else:
		Mod.mod_log(msg, MOD_DPRINT_BASE + (":" + ctx if len(ctx) > 0 else ""))

var mac:     bool = OS.has_feature('OSX')
var windows: bool = OS.has_feature('Windows')
var linux:   bool = OS.has_feature('X11')

func os_command(command_base: String) -> String:
	return command_base + '.exe' if windows else command_base

# Side note, this appears to be the easiest way to check for TrenchBroom (or any other application) 
# on macOS via shell:
# mdfind "kMDItemFSName==TrenchBroom.app" "kMDItemKind == 'Application'" 

func find_tb_in_PATH() -> String:
	var tb_bin_path := ""
	
	var exec_output = []
	var exit_code = OS.execute(os_command("where"), [os_command('TrenchBroom')], true, exec_output)
	
	var trimmed_line: String
	for line in exec_output:
		trimmed_line = (line as String).strip_edges()
		if len(trimmed_line) == 0:
			continue
		
		tb_bin_path = trimmed_line
		break
	
	if not tb_bin_path or len(tb_bin_path) == 0:
		dprint('Failed to resolve a TrenchBroom executable in PATH.')
	
	return tb_bin_path

# Fallback resolution of game defs folder if not configured
func find_tb_game_defs_dir() -> String:
	var dir: Directory = Directory.new()
	var defs_dir = ""
	
	# Try by finding executable
	var tb_bin_path = find_tb_in_PATH()
	if(dir.file_exists(tb_bin_path)):
		# Check executable's directory for game defs
		var tb_bin_dir = tb_bin_path.get_base_dir().plus_file('games')
		if dir.dir_exists(tb_bin_dir):
			dprint('Found TrenchBroom game definitions folder via executable.', 'find_tb_game_defs_dir')
			defs_dir = tb_bin_dir
	
	dprint('Final resolved value: %s' % [ defs_dir if len(defs_dir) > 0 else "<EMPTY-STRING>" ], 'find_tb_game_defs_dir')
	return defs_dir
