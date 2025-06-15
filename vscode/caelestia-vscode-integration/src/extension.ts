import { existsSync } from "fs";
import { readFile, writeFile } from "fs/promises";
import { homedir } from "os";
import { join } from "path";
import { ConfigurationTarget, extensions, RelativePattern, workspace, type ExtensionContext } from "vscode";
import theme from "./theme";

const statedir = () => process.env.XDG_STATE_HOME ?? join(homedir(), ".local", "state");
const schemedir = () => join(statedir(), "caelestia", "scheme");

const update = async () => {
    if (!existsSync(join(schemedir(), "current.txt"))) {
        console.log("No current scheme.");
        return;
    }

    // Update theme colours with scheme
    const scheme = await readFile(join(schemedir(), "current.txt"), "utf-8");
    const colours = scheme.split("\n").reduce((acc, l) => {
        const [name, hex] = l.split(" ");
        acc[name] = `#${hex}`;
        return acc;
    }, {} as { [k: string]: string });

    await writeFile(join(__dirname, "..", "themes", "caelestia.json"), JSON.stringify(theme(colours)));

    // Sync icon theme
    const workbench = workspace.getConfiguration("workbench");
    if (
        workbench.get("colorTheme") === "Caelestia" &&
        /catppuccin-(latte|frappe|macchiato|mocha)/.test(workbench.get("iconTheme") ?? "") &&
        extensions.getExtension("catppuccin.catppuccin-vsc-icons")
    ) {
        const colourMode = await readFile(join(schemedir(), "current-mode.txt"), "utf-8");
        workbench.update(
            "iconTheme",
            `catppuccin-${colourMode === "light" ? "latte" : "mocha"}`,
            ConfigurationTarget.Global
        );
    }

    console.log("Updated scheme.");
};

export const activate = (context: ExtensionContext) => {
    update();
    const watcher = workspace.createFileSystemWatcher(new RelativePattern(schemedir(), "current.txt"));
    context.subscriptions.push(watcher, watcher.onDidCreate(update), watcher.onDidChange(update));
    console.log(`Watching for changes to ${join(schemedir(), "current.txt")}`);
};
