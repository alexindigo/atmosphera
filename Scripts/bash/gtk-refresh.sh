#!/usr/bin/env bash

# Default to ~/.config if not provided
CONFIG_DIR="${1:-$HOME/.config}"

if [ ! -d "$CONFIG_DIR" ]; then
    echo "Error: Config directory not found: $CONFIG_DIR" >&2
    exit 1
fi

apply_gtk3_colors() {
    local config_dir="$1"

    local gtk3_dir="$config_dir/gtk-3.0"
    local colors_file="$gtk3_dir/noctalia.css"
    local gtk_css="$gtk3_dir/gtk.css"

    if [ ! -f "$colors_file" ]; then
        echo "Error: noctalia.css not found at $colors_file" >&2
        echo "Run template processor first to generate theme files" >&2
        exit 1
    fi

    if [ -L "$gtk_css" ]; then
        rm "$gtk_css"
    elif [ -f "$gtk_css" ]; then
        mv "$gtk_css" "$gtk_css.backup.$(date +%s)"
        echo "Backed up existing gtk.css"
    fi

    ln -s "noctalia.css" "$gtk_css"
    echo "Created symlink: $gtk_css -> noctalia.css"
}

apply_gtk4_colors() {
    local config_dir="$1"

    local gtk4_dir="$config_dir/gtk-4.0"
    local colors_file="$gtk4_dir/noctalia.css"
    local gtk_css="$gtk4_dir/gtk.css"
    local gtk4_import="@import url(\"noctalia.css\");"

    if [ ! -f "$colors_file" ]; then
        echo "Error: GTK4 noctalia.css not found at $colors_file" >&2
        echo "Run template processor first to generate theme files" >&2
        exit 1
    fi

    echo "$gtk4_import" > "$gtk_css"
    echo "Updated GTK4 CSS import"
}

refresh_theme() {
    # 1. Get current values
    raw_theme=$(gsettings get org.gnome.desktop.interface gtk-theme)
    current_theme=$(echo "$raw_theme" | tr -d "'")
    
    raw_scheme=$(gsettings get org.gnome.desktop.interface color-scheme)
    current_scheme=$(echo "$raw_scheme" | tr -d "'")
    
    # Fallback defaults if unset
    if [ -z "$current_theme" ]; then current_theme="adw-gtk3-dark"; fi
    if [ -z "$current_scheme" ]; then current_scheme="prefer-dark"; fi
        
    # 2. Toggle Scheme
    if [ "$current_scheme" == "prefer-dark" ]; then
        temp_scheme="default"
    else
        temp_scheme="prefer-dark"
    fi

    gsettings set org.gnome.desktop.interface color-scheme "$temp_scheme"
    dconf write /org/gnome/desktop/interface/color-scheme "'$temp_scheme'"
    
    # 3. Toggle Theme
    gsettings set org.gnome.desktop.interface gtk-theme ""
    dconf write /org/gnome/desktop/interface/gtk-theme "''"
    
    sleep 0.5
    
    # 4. Restore Original Values
    gsettings set org.gnome.desktop.interface color-scheme "$current_scheme"
    dconf write /org/gnome/desktop/interface/color-scheme "'$current_scheme'"
    
    gsettings set org.gnome.desktop.interface gtk-theme "$current_theme"
    dconf write /org/gnome/desktop/interface/gtk-theme "'$current_theme'"
}


mkdir -p "$CONFIG_DIR/gtk-3.0" "$CONFIG_DIR/gtk-4.0"

apply_gtk3_colors "$CONFIG_DIR"
apply_gtk4_colors "$CONFIG_DIR"
refresh_theme

echo "GTK colors applied successfully"