pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

import qs.Commons
import qs.Services.System
import qs.Services.Theming
import qs.Services.UI

Singleton {
  id: root

  readonly property string dynamicConfigPath: Settings.cacheDir + "theming.dynamic.toml"
  readonly property string templateProcessorScript: Quickshell.shellDir + "/Scripts/python/src/theming/template-processor.py"

  readonly property var schemeNameMap: ({
                                          "Noctalia (default)": "Noctalia-default",
                                          "Noctalia (legacy)": "Noctalia-legacy",
                                          "Tokyo Night": "Tokyo-Night",
                                          "Rose Pine": "Rosepine"
                                        })

  readonly property var terminalPaths: ({
                                          "foot": "~/.config/foot/themes/noctalia",
                                          "ghostty": "~/.config/ghostty/themes/noctalia",
                                          "kitty": "~/.config/kitty/themes/noctalia.conf",
                                          "alacritty": "~/.config/alacritty/themes/noctalia.toml",
                                          "wezterm": "~/.config/wezterm/colors/Noctalia.toml"
                                        })

  // Check if a template is enabled in the activeTemplates array
  function isTemplateEnabled(templateId) {
    const activeTemplates = Settings.data.templates.activeTemplates;
    if (!activeTemplates)
      return false;
    for (let i = 0; i < activeTemplates.length; i++) {
      if (activeTemplates[i].id === templateId && activeTemplates[i].enabled) {
        return true;
      }
    }
    return false;
  }

  function escapeTomlString(value) {
    if (!value)
      return "";
    return value.replace(/\\/g, "\\\\").replace(/"/g, '\\"');
  }

  /**
  * Process wallpaper colors using internal themer
  * Dual-path architecture (wallpaper generation)
  */
  function processWallpaperColors(wallpaperPath, mode) {
    const content = buildThemeConfig();
    if (!content)
      return;
    const wp = wallpaperPath.replace(/'/g, "'\\''");

    const script = buildGenerationScript(content, wp, mode);

    generateProcess.command = ["sh", "-lc", script];
    generateProcess.running = true;
  }

  readonly property string schemeJsonPath: Settings.cacheDir + "predefined-scheme.json"
  readonly property string predefinedConfigPath: Settings.cacheDir + "theming.predefined.toml"

  /**
  * Process predefined color scheme using Python template processor
  * Uses --scheme flag to expand 14-color scheme to full 48-color palette
  */
  function processPredefinedScheme(schemeData, mode) {
    // 1. Handle terminal themes (pre-rendered file copy)
    handleTerminalThemes(mode);

    // 2. Build TOML config for application templates
    const tomlContent = buildPredefinedTemplateConfig(mode);
    if (!tomlContent) {
      Logger.d("TemplateProcessor", "No application templates enabled for predefined scheme");
      return;
    }

    // 3. Build script to write files and run Python
    const schemeJsonPathEsc = schemeJsonPath.replace(/'/g, "'\\''");
    const configPathEsc = predefinedConfigPath.replace(/'/g, "'\\''");

    // Use heredoc delimiters for safe JSON/TOML content
    const schemeDelimiter = "SCHEME_JSON_EOF_" + Math.random().toString(36).substr(2, 9);
    const tomlDelimiter = "TOML_CONFIG_EOF_" + Math.random().toString(36).substr(2, 9);

    let script = "";

    // Write scheme JSON
    script += `cat > '${schemeJsonPathEsc}' << '${schemeDelimiter}'\n`;
    script += JSON.stringify(schemeData, null, 2) + "\n";
    script += `${schemeDelimiter}\n`;

    // Write TOML config
    script += `cat > '${configPathEsc}' << '${tomlDelimiter}'\n`;
    script += tomlContent + "\n";
    script += `${tomlDelimiter}\n`;

    // Run Python template processor with --scheme flag
    script += `python3 "${templateProcessorScript}" --scheme '${schemeJsonPathEsc}' --config '${configPathEsc}' --mode ${mode}\n`;

    // Add user templates if enabled
    script += buildUserTemplateCommandForPredefined(schemeData, mode);

    generateProcess.command = ["sh", "-lc", script];
    generateProcess.running = true;
  }

  /**
  * Build TOML config for predefined scheme templates (excludes terminal themes)
  */
  function buildPredefinedTemplateConfig(mode) {
    var lines = [];
    addApplicationTheming(lines, mode);

    if (lines.length > 0) {
      return ["[config]"].concat(lines).join("\n") + "\n";
    }
    return "";
  }

  // ================================================================================
  // WALLPAPER-BASED GENERATION
  // ================================================================================
  function buildThemeConfig() {
    var lines = [];
    var mode = Settings.data.colorSchemes.darkMode ? "dark" : "light";

    if (Settings.data.colorSchemes.useWallpaperColors) {
      addWallpaperTheming(lines, mode);
    }

    addApplicationTheming(lines, mode);

    if (lines.length > 0) {
      return ["[config]"].concat(lines).join("\n") + "\n";
    }
    return "";
  }

  function addWallpaperTheming(lines, mode) {
    const homeDir = Quickshell.env("HOME");
    // Noctalia colors JSON
    lines.push("[templates.noctalia]");
    lines.push('input_path = "' + Quickshell.shellDir + '/Assets/Templates/noctalia.json"');
    lines.push('output_path = "' + Settings.configDir + 'colors.json"');

    // Terminal templates
    TemplateRegistry.terminals.forEach(terminal => {
                                         if (isTemplateEnabled(terminal.id)) {
                                           lines.push(`\n[templates.${terminal.id}]`);
                                           lines.push(`input_path = "${Quickshell.shellDir}/Assets/Templates/${terminal.templatePath}"`);
                                           const outputPath = terminal.outputPath.replace("~", homeDir);
                                           lines.push(`output_path = "${outputPath}"`);
                                           const postHook = terminal.postHook || `${TemplateRegistry.templateApplyScript} ${terminal.id}`;
                                           const postHookEsc = escapeTomlString(postHook);
                                           lines.push(`post_hook = "${postHookEsc}"`);
                                         }
                                       });
  }

  function addApplicationTheming(lines, mode) {
    const homeDir = Quickshell.env("HOME");
    TemplateRegistry.applications.forEach(app => {
                                            if (app.id === "discord") {
                                              // Handle Discord clients specially
                                              if (isTemplateEnabled("discord")) {
                                                app.clients.forEach(client => {
                                                                      // Check if this specific client is detected
                                                                      if (isDiscordClientEnabled(client.name)) {
                                                                        lines.push(`\n[templates.discord_${client.name}]`);
                                                                        lines.push(`input_path = "${Quickshell.shellDir}/Assets/Templates/${app.input}"`);
                                                                        const outputPath = client.path.replace("~", homeDir) + "/themes/noctalia.theme.css";
                                                                        lines.push(`output_path = "${outputPath}"`);
                                                                      }
                                                                    });
                                              }
                                            } else if (app.id === "code") {
                                              // Handle Code clients specially
                                              if (isTemplateEnabled("code")) {
                                                app.clients.forEach(client => {
                                                                      // Check if this specific client is detected
                                                                      if (isCodeClientEnabled(client.name)) {
                                                                        lines.push(`\n[templates.code_${client.name}]`);
                                                                        lines.push(`input_path = "${Quickshell.shellDir}/Assets/Templates/${app.input}"`);
                                                                        const expandedPath = client.path.replace("~", homeDir);
                                                                        lines.push(`output_path = "${expandedPath}"`);
                                                                      }
                                                                    });
                                              }
                                            } else if (app.id === "emacs" && app.checkDoomFirst) {
                                              if (isTemplateEnabled("emacs")) {
                                                const doomPathTemplate = app.outputs[0].path; // ~/.config/doom/themes/noctalia-theme.el
                                                const standardPathTemplate = app.outputs[1].path; // ~/.emacs.d/themes/noctalia-theme.el
                                                const doomPath = doomPathTemplate.replace("~", homeDir);
                                                const standardPath = standardPathTemplate.replace("~", homeDir);
                                                const doomConfigDir = `${homeDir}/.config/doom`;
                                                const doomDir = doomPath.substring(0, doomPath.lastIndexOf('/'));

                                                lines.push(`\n[templates.emacs]`);
                                                lines.push(`input_path = "${Quickshell.shellDir}/Assets/Templates/${app.input}"`);
                                                lines.push(`output_path = "${standardPath}"`);
                                                // Move to doom if doom exists, then remove empty .emacs.d/themes and .emacs.d directories
                                                // Check directories are empty before removing
                                                const postHook = `sh -c 'if [ -d "${doomConfigDir}" ] && [ -f "${standardPath}" ]; then mkdir -p "${doomDir}" && mv "${standardPath}" "${doomPath}" && rmdir "${homeDir}/.emacs.d/themes" 2>/dev/null && rmdir "${homeDir}/.emacs.d" 2>/dev/null || true; fi'`;
                                                const postHookEsc = escapeTomlString(postHook);
                                                lines.push(`post_hook = "${postHookEsc}"`);
                                              }
                                            } else {
                                              // Handle regular apps
                                              if (isTemplateEnabled(app.id)) {
                                                app.outputs.forEach((output, idx) => {
                                                                      lines.push(`\n[templates.${app.id}_${idx}]`);
                                                                      const inputFile = output.input || app.input;
                                                                      lines.push(`input_path = "${Quickshell.shellDir}/Assets/Templates/${inputFile}"`);
                                                                      const outputPath = output.path.replace("~", homeDir);
                                                                      lines.push(`output_path = "${outputPath}"`);
                                                                      if (app.postProcess) {
                                                                        const postHook = escapeTomlString(app.postProcess(mode));
                                                                        lines.push(`post_hook = "${postHook}"`);
                                                                      }
                                                                    });
                                              }
                                            }
                                          });
  }

  function isDiscordClientEnabled(clientName) {
    // Check ProgramCheckerService to see if client is detected
    for (var i = 0; i < ProgramCheckerService.availableDiscordClients.length; i++) {
      if (ProgramCheckerService.availableDiscordClients[i].name === clientName) {
        return true;
      }
    }
    return false;
  }

  function isCodeClientEnabled(clientName) {
    // Check ProgramCheckerService to see if client is detected
    for (var i = 0; i < ProgramCheckerService.availableCodeClients.length; i++) {
      if (ProgramCheckerService.availableCodeClients[i].name === clientName) {
        return true;
      }
    }
    return false;
  }

  // Get scheme type, defaulting to tonal-spot if not a recognized value
  function getSchemeType() {
    const method = Settings.data.colorSchemes.generationMethod;
    const validTypes = ["tonal-spot", "fruit-salad", "rainbow", "vibrant", "faithful"];
    return validTypes.includes(method) ? method : "tonal-spot";
  }

  function buildGenerationScript(content, wallpaper, mode) {
    const delimiter = "THEME_CONFIG_EOF_" + Math.random().toString(36).substr(2, 9);
    const pathEsc = dynamicConfigPath.replace(/'/g, "'\\''");
    const wpDelimiter = "WALLPAPER_PATH_EOF_" + Math.random().toString(36).substr(2, 9);

    // Use heredoc for wallpaper path to avoid all escaping issues
    let script = `cat > '${pathEsc}' << '${delimiter}'\n${content}\n${delimiter}\n`;
    script += `NOCTALIA_WP_PATH=$(cat << '${wpDelimiter}'\n${wallpaper}\n${wpDelimiter}\n)\n`;

    // Use template-processor.py (Python implementation)
    const schemeType = getSchemeType();
    script += `python3 "${templateProcessorScript}" "$NOCTALIA_WP_PATH" --scheme-type ${schemeType} --config '${pathEsc}' --mode ${mode} `;

    script += buildUserTemplateCommand("$NOCTALIA_WP_PATH", mode);

    return script + "\n";
  }

  // ================================================================================
  // TERMINAL THEMES (predefined schemes use pre-rendered files)
  // ================================================================================
  function escapeShellPath(path) {
    // Escape single quotes by ending the quoted string, adding an escaped quote, and starting a new quoted string
    return "'" + path.replace(/'/g, "'\\''") + "'";
  }

  function handleTerminalThemes(mode) {
    const commands = [];
    const homeDir = Quickshell.env("HOME");

    Object.keys(terminalPaths).forEach(terminal => {
                                         if (isTemplateEnabled(terminal)) {
                                           const outputPath = terminalPaths[terminal].replace("~", homeDir);
                                           const outputDir = outputPath.substring(0, outputPath.lastIndexOf('/'));
                                           const templatePaths = getTerminalColorsTemplate(terminal, mode);

                                           commands.push(`mkdir -p ${escapeShellPath(outputDir)}`);
                                           // Try hyphen first (most common), then space (for schemes like "Rosey AMOLED")
                                           const hyphenPath = escapeShellPath(templatePaths.hyphen);
                                           const spacePath = escapeShellPath(templatePaths.space);
                                           commands.push(`if [ -f ${hyphenPath} ]; then cp -f ${hyphenPath} ${escapeShellPath(outputPath)}; elif [ -f ${spacePath} ]; then cp -f ${spacePath} ${escapeShellPath(outputPath)}; else echo "ERROR: Template file not found for ${terminal} (tried both hyphen and space patterns)"; fi`);
                                           commands.push(`${TemplateRegistry.templateApplyScript} ${terminal}`);
                                         }
                                       });

    if (commands.length > 0) {
      copyProcess.command = ["sh", "-lc", commands.join('; ')];
      copyProcess.running = true;
    }
  }

  function getTerminalColorsTemplate(terminal, mode) {
    let colorScheme = Settings.data.colorSchemes.predefinedScheme;
    colorScheme = schemeNameMap[colorScheme] || colorScheme;

    let extension = "";
    if (terminal === 'kitty') {
      extension = ".conf";
    } else if (terminal === 'wezterm') {
      extension = ".toml";
    }

    // Support both naming conventions: "SchemeName-dark" (hyphen) and "SchemeName dark" (space)
    const fileNameHyphen = `${colorScheme}-${mode}${extension}`;
    const fileNameSpace = `${colorScheme} ${mode}${extension}`;
    const relativePathHyphen = `terminal/${terminal}/${fileNameHyphen}`;
    const relativePathSpace = `terminal/${terminal}/${fileNameSpace}`;

    // Try to find the scheme in the loaded schemes list to determine which directory it's in
    for (let i = 0; i < ColorSchemeService.schemes.length; i++) {
      const schemeJsonPath = ColorSchemeService.schemes[i];
      // Check if this is the scheme we're looking for
      if (schemeJsonPath.indexOf(`/${colorScheme}/`) !== -1 || schemeJsonPath.indexOf(`/${colorScheme}.json`) !== -1) {
        // Extract the scheme directory from the JSON path
        // JSON path is like: /path/to/scheme/SchemeName/SchemeName.json
        // We need: /path/to/scheme/SchemeName/terminal/...
        const schemeDir = schemeJsonPath.substring(0, schemeJsonPath.lastIndexOf('/'));
        return {
          hyphen: `${schemeDir}/${relativePathHyphen}`,
          space: `${schemeDir}/${relativePathSpace}`
        };
      }
    }

    // Fallback: try downloaded first, then preinstalled
    const downloadedPathHyphen = `${ColorSchemeService.downloadedSchemesDirectory}/${colorScheme}/${relativePathHyphen}`;
    const downloadedPathSpace = `${ColorSchemeService.downloadedSchemesDirectory}/${colorScheme}/${relativePathSpace}`;
    const preinstalledPathHyphen = `${ColorSchemeService.schemesDirectory}/${colorScheme}/${relativePathHyphen}`;
    const preinstalledPathSpace = `${ColorSchemeService.schemesDirectory}/${colorScheme}/${relativePathSpace}`;

    return {
      hyphen: preinstalledPathHyphen,
      space: preinstalledPathSpace
    };
  }

  // ================================================================================
  // USER TEMPLATES, advanced usage
  // ================================================================================
  function buildUserTemplateCommand(input, mode) {
    if (!Settings.data.templates.enableUserTheming)
      return "";

    const userConfigPath = getUserConfigPath();
    let script = "\n# Execute user config if it exists\n";
    script += `if [ -f '${userConfigPath}' ]; then\n`;
    // If input is a shell variable (starts with $), use double quotes to allow expansion
    // Otherwise, use single quotes for safety with file paths
    const inputQuoted = input.startsWith("$") ? `"${input}"` : `'${input.replace(/'/g, "'\\''")}'`;

    const schemeType = getSchemeType();
    script += `  python3 "${templateProcessorScript}" ${inputQuoted} --scheme-type ${schemeType} --config '${userConfigPath}' --mode ${mode}\n`;
    script += "fi";

    return script;
  }

  function buildUserTemplateCommandForPredefined(schemeData, mode) {
    if (!Settings.data.templates.enableUserTheming)
      return "";

    const userConfigPath = getUserConfigPath();

    // Reuse the scheme JSON already written by processPredefinedScheme()
    const schemeJsonPathEsc = schemeJsonPath.replace(/'/g, "'\\''");

    let script = "\n# Execute user templates with predefined scheme colors\n";
    script += `if [ -f '${userConfigPath}' ]; then\n`;
    // Use --scheme flag with the already-written scheme JSON
    script += `  python3 "${templateProcessorScript}" --scheme '${schemeJsonPathEsc}' --config '${userConfigPath}' --mode ${mode}\n`;
    script += "fi";

    return script;
  }

  function getUserConfigPath() {
    return (Settings.configDir + "user-templates.toml").replace(/'/g, "'\\''");
  }

  // ================================================================================
  // PROCESSES
  // ================================================================================
  Process {
    id: generateProcess
    workingDirectory: Quickshell.shellDir
    running: false

    // Error reporting helpers
    function buildErrorMessage() {
      const title = I18n.tr(`toast.theming-processor-failed.title`);
      const description = (stderr.text && stderr.text.trim() !== "") ? stderr.text.trim() : ((stdout.text && stdout.text.trim() !== "") ? stdout.text.trim() : I18n.tr("toast.theming-processor-failed.desc-generic"));
      return description;
    }

    onExited: function (exitCode) {
      if (exitCode !== 0) {
        const description = generateProcess.buildErrorMessage();
        Logger.e("TemplateProcessor", `Process failed (generator: ${generator}) with exit code`, exitCode, description);
        Logger.d("TemplateProcessor", "Failed command:", command.join(" ").substring(0, 500));
      }
    }

    stdout: StdioCollector {
      onStreamFinished: {
        if (this.text)
        Logger.d("TemplateProcessor", "stdout:", this.text);
      }
    }

    stderr: StdioCollector {
      onStreamFinished: {
        if (this.text && this.text.trim() !== "") {
          // Log template errors/warnings from Python script
          Logger.e("TemplateProcessor", this.text.trim());
        }
      }
    }
  }

  // ------------
  Process {
    id: copyProcess
    workingDirectory: Quickshell.shellDir
    running: false
    stderr: StdioCollector {
      onStreamFinished: {
        if (this.text) {
          Logger.e("TemplateProcessor", "copyProcess stderr:", this.text);
        }
      }
    }
  }
}
