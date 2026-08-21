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

// Destinations shown in the menu. Each entry is [label, scp target]. The
// target is a host, optionally host:/dir (clip2remote.sh defaults dir to
// /tmp). Edit this list to add or remove hosts; the same file ships to every
// machine, so the menu is identical everywhere.
const DESTINATIONS = [
    ['bitforge', 'bitforge.home.lan'],
    ['omie', 'omie.home.lan'],
    ['twelve', 'twelve.home.lan'],
];

// clip2remote.sh lives in the conf-files repo, at the same path on every host.
const CLIP2REMOTE = GLib.build_filenamev([
    GLib.get_home_dir(), 'conf-files', 'scripts', 'clip2remote.sh',
]);

const Clip2RemoteIndicator = GObject.registerClass(
class Clip2RemoteIndicator extends PanelMenu.Button {
    _init() {
        super._init(0.0, 'clip2remote');

        this.add_child(new St.Icon({
            icon_name: 'insert-image-symbolic',
            style_class: 'system-status-icon',
        }));

        for (const [label, target] of DESTINATIONS) {
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
