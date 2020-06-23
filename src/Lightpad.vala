using Gtk;

/*
* budgie-lightpad-applet
* Author: Budgie Desktop Developers
* Copyright 2020 Ubuntu Budgie Developers
* Website=https://ubuntubudgie.org
* This program is free software: you can redistribute it and/or modify it
* under the terms of the GNU General Public License as published by the Free
* Software Foundation, either version 3 of the License, or any later version.
* This program is distributed in the hope that it will be useful, but WITHOUT
* ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
* FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
* more details. You should have received a copy of the GNU General Public
* License along with this program.  If not, see
* <https://www.gnu.org/licenses/>.
*/

namespace LightpadApplet {

    [GtkTemplate (ui = "/org/ubuntubudgie/lightpad/settings.ui")]
    public class LightpadSettings : Gtk.Grid
    {

        [GtkChild]
        private Gtk.Switch? switch_menu_label;

        [GtkChild]
        private Gtk.Entry? entry_label;

        [GtkChild]
        private Gtk.Entry? entry_icon_pick;

        [GtkChild]
        private Gtk.Button? button_icon_pick;

        private GLib.Settings? settings;

        public LightpadSettings(GLib.Settings? settings)
        {
            this.settings = settings;
            settings.bind("enable-menu-label", switch_menu_label, "active", SettingsBindFlags.DEFAULT);
            settings.bind("menu-label", entry_label, "text", SettingsBindFlags.DEFAULT);
            settings.bind("menu-icon", entry_icon_pick, "text", SettingsBindFlags.DEFAULT);

            this.button_icon_pick.clicked.connect(on_pick_click);
        }

        /**
        * Handle the icon picker
        */
        void on_pick_click()
        {
            Lightpad.IconChooser chooser = new Lightpad.IconChooser(this.get_toplevel() as Gtk.Window);
            string? response = chooser.run();
            chooser.destroy();
            if (response != null) {
                this.entry_icon_pick.set_text(response);
            }
        }
    }


    public class Plugin : Budgie.Plugin, Peas.ExtensionBase {
        public Budgie.Applet get_panel_widget(string uuid) {
            return new LightpadApplet(uuid);
        }
    }

    public class LightpadApplet : Budgie.Applet {

        private Gtk.ToggleButton widget;
        public string uuid { public set; public get; }

        protected GLib.Settings settings;

        Gtk.Image img;
        Gtk.Label label;
        Budgie.PanelPosition panel_position = Budgie.PanelPosition.BOTTOM;
        int pixel_size = 32;

        /* specifically to the settings section */
        public override bool supports_settings()
        {
            return true;
        }
        public override Gtk.Widget? get_settings_ui()
        {
            return new LightpadSettings(this.get_applet_settings(uuid));
        }

        public LightpadApplet(string uuid) {
            GLib.Object(uuid: uuid);

            settings_schema = "com.solus-project.budgie-menu";
            settings_prefix = "/org/solus-project/budgie-panel/instance/budgie-menu";

            settings = this.get_applet_settings(uuid);

            settings.changed.connect(on_settings_changed);

            /* Panel Menu Button */
            widget = new Gtk.ToggleButton();
            widget.relief = Gtk.ReliefStyle.NONE;
            img = new Gtk.Image.from_icon_name("view-grid-symbolic", Gtk.IconSize.INVALID);
            img.pixel_size = pixel_size;
            img.no_show_all = true;

            var layout = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
            layout.pack_start(img, true, true, 0);
            label = new Gtk.Label("");
            label.halign = Gtk.Align.START;
            layout.pack_start(label, true, true, 3);

            /* set icon */
            widget.add(layout);

            // Better styling to fit in with the budgie-panel
            var st = widget.get_style_context();
            st.add_class("budgie-menu-launcher");
            st.add_class("panel-button");

            supported_actions = Budgie.PanelAction.MENU;

            /* On Press Menu Button */
            widget.button_press_event.connect((e)=> {
                if (e.button != 1) {
                    return Gdk.EVENT_PROPAGATE;
                }
                Process.spawn_command_line_async("com.github.libredeb.lightpad");
                return Gdk.EVENT_STOP;
            });
            add(widget);
            show_all();

            on_settings_changed("enable-menu-label");
            on_settings_changed("menu-icon");
            on_settings_changed("menu-label");

            /* Potentially reload icon on pixel size jumps */
            panel_size_changed.connect((p,i,s)=> {
                if (this.pixel_size != i) {
                    this.pixel_size = (int)i;
                    this.on_settings_changed("menu-icon");
                }
            });

        }

        public override void panel_position_changed(Budgie.PanelPosition position)
        {
            this.panel_position = position;
            bool vertical = (position == Budgie.PanelPosition.LEFT || position == Budgie.PanelPosition.RIGHT);
            int margin = vertical ? 0 : 3;
            img.set_margin_end(margin);
            on_settings_changed("enable-menu-label");
        }

        protected void on_settings_changed(string key) {
            bool should_show = true;

            switch (key)
            {
                case "menu-icon":
                    string? icon = settings.get_string(key);
                    if ("/" in icon) {
                        try {
                            Gdk.Pixbuf pixbuf = new Gdk.Pixbuf.from_file(icon);
                            img.set_from_pixbuf(pixbuf.scale_simple(this.pixel_size, this.pixel_size, Gdk.InterpType.BILINEAR));
                        } catch (Error e) {
                            warning("Failed to update Budgie Menu applet icon: %s", e.message);
                            img.set_from_icon_name("view-grid-symbolic", Gtk.IconSize.INVALID); // Revert to view-grid-symbolic
                        }
                    } else if (icon == "") {
                        should_show = false;
                    } else {
                        img.set_from_icon_name(icon, Gtk.IconSize.INVALID);
                    }
                    img.set_pixel_size(this.pixel_size);
                    img.set_visible(should_show);
                    break;
                case "menu-label":
                    label.set_label(settings.get_string(key));
                    break;
                case "enable-menu-label":
                    bool visible = (panel_position == Budgie.PanelPosition.TOP ||
                                    panel_position == Budgie.PanelPosition.BOTTOM) &&
                                    settings.get_boolean(key);
                    label.set_visible(visible);
                    break;
                default:
                    break;
            }
        }

        public override void invoke_action(Budgie.PanelAction action) {
            if ((action & Budgie.PanelAction.MENU) != 0) {
                Process.spawn_command_line_async("com.github.libredeb.lightpad");
            }
        }

    }
}


[ModuleInit]
public void peas_register_types(TypeModule module){
    /* boilerplate - all modules need this */
    var objmodule = module as Peas.ObjectModule;
    objmodule.register_extension_type(typeof(
        Budgie.Plugin), typeof(LightpadApplet.Plugin)
    );
}