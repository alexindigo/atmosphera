-- Atmosphera Hyprland layer (Lua syntax, Hyprland >= 0.55)
-- Installed by atmosphera-hypr-setup to ~/.config/hypr/atmosphera.lua.
-- Startup lines (exec-once) are appended by the setup script per route.

-- Blur Atmosphera's layer-shell surfaces (bars, panels, OSD).
hl.layer_rule({ match = { namespace = "^atmosphera-.*$" }, blur = true })
