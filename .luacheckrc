std = "lua51"
max_line_length = false
exclude_files = { "VignetteRadar_*.lua", "Media/**" }
-- WoW API globals are checked by LuaLS with the WoW annotations; luacheck only checks logic.
allow_defined_top = true
ignore = { "113", "143", "212/self", "212/_.*" }
