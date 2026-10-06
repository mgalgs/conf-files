// clip2remote GNOME Shell extension
//
// Adds a panel button whose menu lists a set of destination hosts. Clicking a
// destination uploads the current clipboard image to that host (via
// clip2remote.sh --print-only <target>) and copies the resulting remote path
// to the clipboard, so you can paste it into a Claude Code / editor session
// running on that host over SSH.
//
// GNOME Shell 45+ (ES modules).

import GObject from 'gi://GObject';
import St from 'gi://St';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';

import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';

// Destinations come from a local file that this repo does NOT track, so no
// private hostnames live in version control:
//   ~/.config/clip2remote/destinations
// One destination per line: "<label>  <ssh-target>". The target is a host,
// optionally host:/dir (clip2remote.sh defaults the dir to /tmp). Blank lines
// and lines starting with # are ignored. A line with a single field uses it
// as both label and target. See destinations.example.
const DEST_FILE = GLib.build_filenamev([
    GLib.get_user_config_dir(), 'clip2remote', 'destinations',
]);

// clip2remote.sh lives in the conf-files repo, at the same path on every host.
const CLIP2REMOTE = GLib.build_filenamev([
    GLib.get_home_dir(), 'conf-files', 'scripts', 'clip2remote.sh',
]);

function readDestinations() {
    let text;
    try {
        const [ok, bytes] = GLib.file_get_contents(DEST_FILE);
        if (!ok)
            return [];
        text = new TextDecoder().decode(bytes);
    } catch (_e) {
        return []; // missing or unreadable file
    }

    const dests = [];
    for (const raw of text.split('\n')) {
        const line = raw.trim();
        if (!line || line.startsWith('#'))
            continue;
        const parts = line.split(/\s+/);
        const label = parts[0];
        const target = parts.length > 1 ? parts.slice(1).join(' ') : parts[0];
        dests.push([label, target]);
    }
    return dests;
}

const Clip2RemoteIndicator = GObject.registerClass(
class Clip2RemoteIndicator extends PanelMenu.Button {
    _init() {
        super._init(0.0, 'clip2remote');

        this.add_child(new St.Icon({
            icon_name: 'insert-image-symbolic',
            style_class: 'system-status-icon',
        }));

        this._rebuild();

        // Re-read the config each time the menu opens, so edits to the
        // destinations file take effect without reloading the extension.
        this.menu.connect('open-state-changed', (_menu, open) => {
            if (open)
                this._rebuild();
        });
    }

    _rebuild() {
        this.menu.removeAll();
        const dests = readDestinations();

        if (dests.length === 0) {
            const item = new PopupMenu.PopupMenuItem(
                `No destinations — create ${DEST_FILE}`);
            item.setSensitive(false);
            this.menu.addMenuItem(item);
            return;
        }

        for (const [label, target] of dests) {
            const item = new PopupMenu.PopupMenuItem(`Push clipboard image → ${label}`);
            item.connect('activate', () => this._push(label, target));
            this.menu.addMenuItem(item);
        }
    }

    _push(label, target) {
        let proc;
        try {
            proc = Gio.Subprocess.new(
                [CLIP2REMOTE, '--print-only', target],
                Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_PIPE
            );
        } catch (e) {
            Main.notifyError('clip2remote', `Could not launch clip2remote.sh: ${e.message}`);
            return;
        }

        proc.communicate_utf8_async(null, null, (p, res) => {
            let ok, stdout, stderr;
            try {
                [ok, stdout, stderr] = p.communicate_utf8_finish(res);
            } catch (e) {
                Main.notifyError('clip2remote', `Error talking to clip2remote.sh: ${e.message}`);
                return;
            }

            if (!p.get_successful()) {
                const msg = (stderr || '').trim() || `exited ${p.get_exit_status()}`;
                Main.notifyError(`clip2remote → ${label} failed`, msg);
                return;
            }

            const path = (stdout || '').trim();
            if (!path) {
                Main.notifyError('clip2remote', `No path returned from ${label}`);
                return;
            }

            St.Clipboard.get_default().set_text(St.ClipboardType.CLIPBOARD, path);
            Main.notify(`clip2remote → ${label}`, `Copied to clipboard:\n${path}`);
        });
    }
});

export default class Clip2RemoteExtension extends Extension {
    enable() {
        this._indicator = new Clip2RemoteIndicator();
        Main.panel.addToStatusArea(this.uuid, this._indicator);
    }

    disable() {
        this._indicator?.destroy();
        this._indicator = null;
    }
}
