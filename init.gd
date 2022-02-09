extends Node

# Mod Info
const MOD_ID = "trenchbroom-config"
const MOD_ID_SHORT = "tb-conf"
const MODS_DIR = "res://MOD_CONTENT"
const MOD_BASE = MODS_DIR + "/" + MOD_ID


const MOD_DPRINT_BASE = MOD_ID_SHORT
func dprint(msg: String, ctx: String = "") -> void:
	if Engine.editor_hint:
		print("[%s] %s" % [ MOD_DPRINT_BASE + (":" + ctx if len(ctx) > 0 else ""), msg])
	else:
		Mod.mod_log(msg, MOD_DPRINT_BASE + (":" + ctx if len(ctx) > 0 else ""))

const DEFAULT_USER_GAMES_DIR = 'user://game-defs'

# Config
const CONFIG_FILE_PATH = 'user://%s.cfg' % [ MOD_ID_SHORT ]
var config: ConfigFile

func _config_init() -> void:
	config = ConfigFile.new()

	var file = File.new()
	# Initialize config file if file doesn't exist
	if not file.file_exists(CONFIG_FILE_PATH):
		dprint('Initializing config file %s' % [ CONFIG_FILE_PATH ], '_config_init')

		# Create default config file
		config.set_value("output", "games_folder", DEFAULT_USER_GAMES_DIR)
		config.set_value("output", "custom_icon_path", GAME_CONFIG_FOLDER_CUSTOM_ICON_PATH)
		config.set_value("output", "game_name", GAME_CONFIG_FOLDER_CUSTOM_NAME)

		# Write it
		var err := config.save(CONFIG_FILE_PATH)
		if err != OK:
			dprint('[WARNING] Error initializing config file: %s' % [ err ], '_config_init')

	else:
		var err = config.load(CONFIG_FILE_PATH)
		if err != OK:
			dprint('[WARNING] Error loading config file: %s' % [ err ], '_config_init')

func _init() -> void:
	dprint('', 'on:init')

	dprint('Loading config', 'on:init')
	_config_init()

	# Connect post-modload handler for exporting folder
	dprint('Adding post-modload hook for building game defs', 'on:init')
	Mod.connect("modloading_complete", self, "_on_modloading_complete")


func _on_modloading_complete():
	write_game_config()

# Main export function
func write_game_config():
	var game_defs_dir: String = config.get_value("output", "games_folder", DEFAULT_USER_GAMES_DIR)
	var custom_icon_path = config.get_value("output", "custom_icon_path", GAME_CONFIG_FOLDER_CUSTOM_ICON_PATH)
	var game_name: String = config.get_value("output", "game_name", GAME_CONFIG_FOLDER_CUSTOM_NAME)

	var dir: Directory = Directory.new()

	# Check defs folder exists
	if not dir.dir_exists(game_defs_dir):
		# Check its not actually a file just in case
		if dir.file_exists(game_defs_dir):
			push_error('Passed directory path is an existing file.')
			return ERR_INVALID_PARAMETER
		# Make it
		var err = dir.make_dir_recursive(game_defs_dir)
		if err != OK:
			push_error('Failed to create game definitions dir: <%s>' %  [ game_defs_dir ])
			return err

	var base_tb_config_folder = preload('res://addons/qodot/game-definitions/trenchbroom/qodot_trenchbroom_config_folder.tres').duplicate()
	base_tb_config_folder.trenchbroom_games_folder = ProjectSettings.globalize_path(game_defs_dir)

	var base_tb_config_file = preload('res://addons/qodot/game-definitions/trenchbroom/qodot_trenchbroom_config_file.tres').duplicate()
	# Replace base template with cleaned up version
	if game_name:
		base_tb_config_folder.game_name = game_name
	base_tb_config_file.base_text = GAME_CONFIG_FILE_BASE_TEXT.replace('name": "Qodot', ('name": "%s' % [ base_tb_config_folder.game_name ]))
	base_tb_config_folder.game_config_file = base_tb_config_file

	# Add custom icon if set up properly
	if dir.file_exists(custom_icon_path):
		dprint('Trying to load custom icon at path <%s>' % [ custom_icon_path ], 'write_game_config')
		if ResourceLoader.exists(custom_icon_path, 'Texture'):
			var custom_icon_tex = load(custom_icon_path)
			if is_instance_valid(custom_icon_tex):
				base_tb_config_folder.icon = custom_icon_tex
				dprint('Using custom icon for game config: <%s>' % [ custom_icon_path ], 'write_game_config')
			else:
				dprint('[WARNING] Found custom icon and validated resource type at path <%s> but instance is not valid.' % [ custom_icon_path ], 'write_game_config')
		else:
			dprint('[WARNING] Found custom icon at path <%s> but failed check if its a Texture' % [ custom_icon_path ], 'write_game_config')

	# The original qodot trenchbroom game config scripted resources have editor context checks in
	# their `set_export_file` functions, so they're replaced with a version of the config folder
	# method with all other's calls inlined.
	export_game_defs(base_tb_config_folder)

# Replacement for set_export_file methods in trenchbroom game resources
func export_game_defs(game_config_folder) -> void:
	if not game_config_folder.trenchbroom_games_folder:
		dprint("Skipping export: No TrenchBroom games folder", 'export_game_defs')
		return

	var config_folder = game_config_folder.trenchbroom_games_folder + "/" + game_config_folder.game_name
	var config_dir = Directory.new()

	var err = config_dir.open(config_folder)
	if err != OK:
		dprint("Couldn't open directory, creating <%s>" % [ config_folder ], 'export_game_defs')
		err = config_dir.make_dir_recursive(config_folder)
		if err != OK:
			dprint("Skipping export: Failed to create directory", 'export_game_defs')
			return

	if not game_config_folder.game_config_file:
		dprint("Skipping export: No game config file", 'export_game_defs')
		return

	if game_config_folder.fgd_files.size() == 0:
		dprint("Skipping export: No FGD files", 'export_game_defs')
		return

	dprint("Exporting TrenchBroom Game Config Folder to %s" % [ config_folder ], 'export_game_defs')

	var icon_path: String = config_folder + "/Icon.png"
	dprint("Exporting icon to %s" % [ icon_path ], 'export_game_defs')

	var export_icon: Image = game_config_folder.icon.get_data()
	export_icon.resize(32, 32, Image.INTERPOLATE_LANCZOS)
	export_icon.save_png(icon_path)

	var export_config_file: TrenchBroomGameConfigFile = game_config_folder.game_config_file.duplicate()
	export_config_file.target_file = config_folder + "/GameConfig.cfg"

	export_config_file.fgd_filenames = []
	for fgd_file in game_config_folder.fgd_files:
		export_config_file.fgd_filenames.append(fgd_file.fgd_name + ".fgd")

	#region Inline TrenchBroomConfigFile.set_export_file

	# export_config_file.set_export_file(true)

	if not export_config_file.target_file:
		dprint("Skipping export: No target file", 'export_game_defs')
		# return

	#endregion Inline TrenchBroomConfigFile.set_export_file

	dprint("Exporting TrenchBroom Game Config File to %s" % [ export_config_file.target_file ], 'export_game_defs')
	var file_obj: = File.new()
	file_obj.open(export_config_file.target_file, File.WRITE)

	file_obj.store_string(
			game_file_build_class_text(export_config_file).replace(
					'name": "Qodot', 'name": "%s' % [ game_config_folder.game_name ]))
	# file_obj.store_string(export_config_file.build_class_text())
	file_obj.close()

	for fgd_file in game_config_folder.fgd_files:
		if not fgd_file is QodotFGDFile:
			dprint("Skipping %s: Not a valid FGD file" % [fgd_file], 'export_game_defs')
			continue

		var export_fgd: QodotFGDFile = fgd_file.duplicate()
		export_fgd.target_folder = config_folder

		#region Inline QodotFGDFile.set_export_file

		# export_fgd.set_export_file(true)

		if export_fgd.get_fgd_classes().size() > 0:
			if not export_fgd.target_folder:
				dprint("Skipping export: No target folder", 'export_game_defs')
				return

			if export_fgd.fgd_name == "":
				dprint("Skipping export: Empty FGD name", 'export_game_defs')

			var fgd_file_path = export_fgd.target_folder + "/" + export_fgd.fgd_name + ".fgd"

			dprint("Exporting FGD to %s" % [ fgd_file_path ], 'export_game_defs')
			var export_fgd_file_obj: = File.new()
			export_fgd_file_obj.open(fgd_file_path, File.WRITE)
			export_fgd_file_obj.store_string(export_fgd.build_class_text())
			export_fgd_file_obj.close()

		#endregion Inline QodotFGDFile.set_export_file

	dprint("Export complete", 'export_game_defs')

func game_file_build_class_text(export_config_file) -> String:

	var fgd_filename_str: = ""
	for fgd_filename in export_config_file.fgd_filenames:
		fgd_filename_str += "\"%s\"" % fgd_filename
		if fgd_filename != export_config_file.fgd_filenames[ - 1]:
			fgd_filename_str += ", "

	var brush_tags_str = export_config_file.parse_tags(export_config_file.brush_tags)
	var face_tags_str = export_config_file.parse_tags(export_config_file.face_tags)
	var surface_flags_str = export_config_file.parse_flags(export_config_file.face_attrib_surface_flags)
	var content_flags_str = export_config_file.parse_flags(export_config_file.face_attrib_content_flags)

	return GAME_CONFIG_FILE_BASE_TEXT % [
		fgd_filename_str,
		brush_tags_str,
		face_tags_str,
		surface_flags_str,
		content_flags_str
	]

const GAME_CONFIG_FOLDER_CUSTOM_NAME := 'Cruelty Squad'
const GAME_CONFIG_FOLDER_CUSTOM_ICON_PATH := MOD_BASE + '/assets/custom_icon.png'

const GAME_CONFIG_FILE_BASE_TEXT := """{
	"version": 3,
	"name": "Qodot",
	"icon": "Icon.png",
	"fileformats": [
		{ "format": "Valve", "initialmap": "initial_valve.map" }
	],
	"filesystem": {
		"searchpath": ".",
		"packageformat": { "extension": "pak", "format": "idpak" }
	},
	"textures": {
		"package": { "type": "directory", "root": "textures" },
		"format": { "extensions": ["bmp", "jpeg", "jpg", "png", "tga" ], "format": "image" },
		"attribute": "_tb_textures"
	},
	"entities": {
		"definitions": [ %s ],
		"defaultcolor": "0.6 0.6 0.6 1.0",
		"modelformats": [ "mdl", "md2", "md3", "bsp", "dkm" ]
	},
	"tags": {
		"brush": [
			%s
		],
		"brushface": [
			%s
		]
	},
	"faceattribs": {
		"surfaceflags": [
				%s
		],
		"contentflags": [
				%s
		]
	}
}"""
