using Gtk;

/*
 * budgie-lightpad-applet
 * Author: Budgie Desktop Developers
 * Copyright 2020-2026 Ubuntu Budgie Developers
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

	/* ------------------------------------------------------------------ */
	/* Settings keys                                                        */
	/* ------------------------------------------------------------------ */

	const string SETTINGS_SCHEMA           = "com.solus-project.budgie-menu";
	const string SETTINGS_PREFIX           = "/org/solus-project/budgie-panel/instance/budgie-menu";
	const string SETTINGS_KEY_ENABLE_LABEL = "enable-menu-label";
	const string SETTINGS_KEY_LABEL        = "menu-label";
	const string SETTINGS_KEY_ICON         = "menu-icon";

	/* ------------------------------------------------------------------ */
	/* Desktop background GSettings                                        */
	/* ------------------------------------------------------------------ */

	const string BG_SETTINGS_SCHEMA      = "org.gnome.desktop.background";
	const string BG_KEY_PICTURE_URI      = "picture-uri";
	const string BG_KEY_PICTURE_URI_DARK = "picture-uri-dark";

	/* ------------------------------------------------------------------ */
	/* Lightpad executable and background cache                            */
	/* ------------------------------------------------------------------ */

	const string LIGHTPAD_EXECUTABLE  = "io.github.libredeb.lightpad";
	const string LIGHTPAD_BG_ARG      = "--background";
	const string LIGHTPAD_CACHE_DIR   = ".lightpad";
	const string LIGHTPAD_BG_FILENAME = "background.jpg";
	const string LIGHTPAD_BG_MARKER   = "background.source";

	/* ------------------------------------------------------------------ */
	/* ImageMagick blur settings                                           */
	/* ------------------------------------------------------------------ */

	/** Gaussian blur applied via ImageMagick: radius x sigma */
	const string IMAGEMAGICK_BLUR_PARAM = "0x8";
	string? imagemagick_cmd;

	/** Divisor for the GDK pixbuf scale-down fallback blur */
	const int    PIXBUF_BLUR_DIVISOR = 8;
	const string PIXBUF_JPEG_QUALITY = "90";

	/* ------------------------------------------------------------------ */
	/* Panel widget appearance                                             */
	/* ------------------------------------------------------------------ */

	const string DEFAULT_ICON_NAME      = "view-grid-symbolic";
	const string CSS_CLASS_LAUNCHER     = "budgie-menu-launcher";
	const string CSS_CLASS_PANEL_BUTTON = "panel-button";
	const int    DEFAULT_PIXEL_SIZE     = 32;
	const int    LABEL_MARGIN           = 3;


	/* ====================================================================
	 * LightpadSettings — settings panel shown in the Budgie panel editor
	 * ==================================================================== */

	[GtkTemplate (ui = "/org/ubuntubudgie/lightpad/settings.ui")]
	public class LightpadSettings : Gtk.Grid {

		[GtkChild] private unowned Gtk.Switch? switch_menu_label;
		[GtkChild] private unowned Gtk.Entry?  entry_label;
		[GtkChild] private unowned Gtk.Entry?  entry_icon_pick;
		[GtkChild] private unowned Gtk.Button? button_icon_pick;

		private GLib.Settings? settings;

		public LightpadSettings(GLib.Settings? settings) {
			this.settings = settings;
			settings.bind(SETTINGS_KEY_ENABLE_LABEL, switch_menu_label, "active", SettingsBindFlags.DEFAULT);
			settings.bind(SETTINGS_KEY_LABEL,        entry_label,       "text",   SettingsBindFlags.DEFAULT);
			settings.bind(SETTINGS_KEY_ICON,         entry_icon_pick,   "text",   SettingsBindFlags.DEFAULT);

			button_icon_pick.clicked.connect(on_pick_click);
		}

		/** Open a file-chooser dialog and write the chosen path to the icon entry. */
		private void on_pick_click() {
			var chooser = new Lightpad.IconChooser(get_toplevel() as Gtk.Window);
			string? response = chooser.run();
			chooser.destroy();
			if (response != null) {
				entry_icon_pick.set_text(response);
			}
		}
	}


	/* ====================================================================
	 * Plugin — Peas entry point
	 * ==================================================================== */

	public class Plugin : Budgie.Plugin, Peas.ExtensionBase {
		public Budgie.Applet get_panel_widget(string uuid) {
			return new LightpadApplet(uuid);
		}
	}


	/* ====================================================================
	 * LightpadApplet — the panel button that launches Lightpad
	 * ==================================================================== */

	public class LightpadApplet : Budgie.Applet {

		public string uuid { public set; public get; }

		private Gtk.ToggleButton     widget;
		private Gtk.Image            img;
		private Gtk.Label            label;
		private GLib.Settings        settings;
		private GLib.Settings?       bg_settings    = null;
		private Budgie.PanelPosition panel_position = Budgie.PanelPosition.BOTTOM;
		private int                  pixel_size     = DEFAULT_PIXEL_SIZE;

		/* Resolved once at construction; stable for the lifetime of the applet. */
		private string cache_dir;
		private string cached_bg_path;
		private string source_marker_path;


		/* -- Settings UI ------------------------------------------------- */

		public override bool supports_settings() {
			return true;
		}

		public override Gtk.Widget? get_settings_ui() {
			return new LightpadSettings(get_applet_settings(uuid));
		}


		/* -- Construction ------------------------------------------------ */

		public LightpadApplet(string uuid) {
			GLib.Object(uuid: uuid);

			settings_schema = SETTINGS_SCHEMA;
			settings_prefix = SETTINGS_PREFIX;
			settings = get_applet_settings(uuid);

			/* Resolve cache paths once rather than rebuilding on every call. */
			cache_dir          = GLib.Path.build_filename(GLib.Environment.get_home_dir(), LIGHTPAD_CACHE_DIR);
			cached_bg_path     = GLib.Path.build_filename(cache_dir, LIGHTPAD_BG_FILENAME);
			source_marker_path = GLib.Path.build_filename(cache_dir, LIGHTPAD_BG_MARKER);

			resolve_imagemagick_cmd();
			build_widget();
			setup_wallpaper_monitor();
		}

		/**
		 * Cater for v7 and pre v7 forms of the imagemagick utility
		 */

		private void resolve_imagemagick_cmd() {
			imagemagick_cmd = GLib.Environment.find_program_in_path("magick");

			if (imagemagick_cmd == null) {
				imagemagick_cmd = GLib.Environment.find_program_in_path("convert");
			}

			if (imagemagick_cmd == null) {
				warning("Neither 'magick' nor 'convert' found in PATH");
			}
		}

		/**
		 * Create and wire up all GTK widgets for the panel button.
		 * Kept separate from the constructor to improve readability.
		 */
		private void build_widget() {
			widget = new Gtk.ToggleButton();
			widget.relief = Gtk.ReliefStyle.NONE;

			img = new Gtk.Image.from_icon_name(DEFAULT_ICON_NAME, Gtk.IconSize.INVALID);
			img.pixel_size = pixel_size;
			img.no_show_all = true;

			label = new Gtk.Label("");
			label.halign = Gtk.Align.START;

			var layout = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
			layout.pack_start(img,   true, true, 0);
			layout.pack_start(label, true, true, LABEL_MARGIN);

			widget.add(layout);

			var style = widget.get_style_context();
			style.add_class(CSS_CLASS_LAUNCHER);
			style.add_class(CSS_CLASS_PANEL_BUTTON);

			supported_actions = Budgie.PanelAction.MENU;

			widget.button_press_event.connect((e) => {
				if (e.button != 1) {
					return Gdk.EVENT_PROPAGATE;
				}
				launch_lightpad();
				return Gdk.EVENT_STOP;
			});

			add(widget);
			show_all();

			settings.changed.connect(on_settings_changed);
			on_settings_changed(SETTINGS_KEY_ICON);
			on_settings_changed(SETTINGS_KEY_LABEL);
			on_settings_changed(SETTINGS_KEY_ENABLE_LABEL);

			panel_size_changed.connect((p, i, s) => {
				if (pixel_size != i) {
					pixel_size = (int) i;
					on_settings_changed(SETTINGS_KEY_ICON);
				}
			});
		}


		/* -- Panel callbacks --------------------------------------------- */

		public override void panel_position_changed(Budgie.PanelPosition position) {
			panel_position = position;
			bool vertical  = (position == Budgie.PanelPosition.LEFT ||
							   position == Budgie.PanelPosition.RIGHT);
			img.set_margin_end(vertical ? 0 : LABEL_MARGIN);
			on_settings_changed(SETTINGS_KEY_ENABLE_LABEL);
		}

		public override void invoke_action(Budgie.PanelAction action) {
			if ((action & Budgie.PanelAction.MENU) != 0) {
				launch_lightpad();
			}
		}

		private void on_settings_changed(string key) {
			switch (key) {
				case SETTINGS_KEY_ICON:
					update_icon(settings.get_string(key));
					break;
				case SETTINGS_KEY_LABEL:
					label.set_label(settings.get_string(key));
					break;
				case SETTINGS_KEY_ENABLE_LABEL:
					bool horizontal = (panel_position == Budgie.PanelPosition.TOP ||
									   panel_position == Budgie.PanelPosition.BOTTOM);
					label.set_visible(horizontal && settings.get_boolean(key));
					break;
			}
		}

		/**
		 * Apply the icon setting to the panel button image.
		 * An empty string hides the image; a path loads a pixbuf;
		 * anything else is treated as a named icon.
		 */
		private void update_icon(string icon) {
			if (icon == "") {
				img.set_visible(false);
				return;
			}

			if ("/" in icon) {
				try {
					var pixbuf = new Gdk.Pixbuf.from_file(icon);
					img.set_from_pixbuf(
						pixbuf.scale_simple(pixel_size, pixel_size, Gdk.InterpType.BILINEAR)
					);
				} catch (Error e) {
					warning("Could not load icon from path '%s': %s", icon, e.message);
					img.set_from_icon_name(DEFAULT_ICON_NAME, Gtk.IconSize.INVALID);
				}
			} else {
				img.set_from_icon_name(icon, Gtk.IconSize.INVALID);
			}

			img.set_pixel_size(pixel_size);
			img.set_visible(true);
		}

		/** Launch the Lightpad application asynchronously. */
		private void launch_lightpad() {
			try {
				Process.spawn_command_line_async(LIGHTPAD_EXECUTABLE);
			} catch (Error e) {
				critical("Unable to launch %s: %s", LIGHTPAD_EXECUTABLE, e.message);
			}
		}


		/* -- Wallpaper monitoring ---------------------------------------- */

		/**
		 * Bind to the GNOME desktop background schema so that any wallpaper
		 * change triggers a background cache refresh.  Also runs immediately
		 * at startup to ensure the cache is current.
		 */
		private void setup_wallpaper_monitor() {
			bg_settings = new GLib.Settings(BG_SETTINGS_SCHEMA);
			bg_settings.changed[BG_KEY_PICTURE_URI].connect(
				() => sync_lightpad_background()
			);
			sync_lightpad_background();
		}

		/**
		 * Resolve the active wallpaper GSettings URI to an absolute local path.
		 * Falls back to the dark-mode key if the light key is unset.
		 * Returns null if no usable wallpaper path can be determined.
		 */
		private string? resolve_wallpaper_path() {
			string uri = bg_settings.get_string(BG_KEY_PICTURE_URI);
			if (uri == "") {
				uri = bg_settings.get_string(BG_KEY_PICTURE_URI_DARK);
			}
			if (uri == "") {
				return null;
			}

			if (uri.has_prefix("file://")) {
				try {
					return GLib.Filename.from_uri(uri);
				} catch (ConvertError e) {
					warning("Could not convert wallpaper URI '%s': %s", uri, e.message);
					return null;
				}
			}

			return uri;
		}

		/**
		 * Read the wallpaper path that was used to build the current cache.
		 * Returns null when no marker exists or it cannot be read.
		 */
		private string? read_source_marker() {
			if (!GLib.FileUtils.test(source_marker_path, GLib.FileTest.EXISTS)) {
				return null;
			}
			try {
				string contents;
				GLib.FileUtils.get_contents(source_marker_path, out contents);
				return contents.strip();
			} catch (FileError e) {
				warning("Could not read background source marker: %s", e.message);
				return null;
			}
		}

		/** Persist the wallpaper path so future runs can skip re-caching. */
		private void write_source_marker(string wallpaper_path) {
			try {
				GLib.FileUtils.set_contents(source_marker_path, wallpaper_path);
			} catch (FileError e) {
				warning("Could not write background source marker: %s", e.message);
			}
		}

		/**
		 * Check whether the cached background is stale, and if so ask Lightpad
		 * to re-copy the wallpaper then blur the result.
		 *
		 * The marker file (background.source) records which wallpaper path was
		 * last cached.  If it matches the current wallpaper and background.jpg
		 * already exists, nothing needs to be done.
		 */
		private void sync_lightpad_background() {
			string? wallpaper_path = resolve_wallpaper_path();
			if (wallpaper_path == null) {
				return;
			}

			string? cached_source  = read_source_marker();
			bool    cache_is_current = (cached_source == wallpaper_path &&
										GLib.FileUtils.test(cached_bg_path, GLib.FileTest.EXISTS));
			if (cache_is_current) {
				return;
			}

			ensure_cache_dir();

			if (!copy_wallpaper_via_lightpad(wallpaper_path)) {
				return;
			}

			blur_cached_background();
			write_source_marker(wallpaper_path);
		}

		/** Create the cache directory if it does not already exist. */
		private void ensure_cache_dir() {
			if (!GLib.FileUtils.test(cache_dir, GLib.FileTest.IS_DIR)) {
				GLib.DirUtils.create_with_parents(cache_dir, 0755);
			}
		}

		/**
		 * Run `lightpad --background <path>` synchronously so the cached file
		 * is guaranteed to exist before blur_cached_background() is called.
		 * Returns false and logs a warning on failure.
		 */
		private bool copy_wallpaper_via_lightpad(string wallpaper_path) {
			try {
				int exit_status;
				GLib.Process.spawn_sync(
					null,
					{ LIGHTPAD_EXECUTABLE, LIGHTPAD_BG_ARG, wallpaper_path },
					null,
					GLib.SpawnFlags.SEARCH_PATH,
					null, null, null,
					out exit_status
				);
				if (exit_status != 0) {
					warning("%s %s exited with status %d",
							LIGHTPAD_EXECUTABLE, LIGHTPAD_BG_ARG, exit_status);
					return false;
				}
			} catch (Error e) {
				warning("Failed to run %s %s: %s", LIGHTPAD_EXECUTABLE, LIGHTPAD_BG_ARG, e.message);
				return false;
			}

			if (!GLib.FileUtils.test(cached_bg_path, GLib.FileTest.EXISTS)) {
				warning("%s %s succeeded but '%s' was not created",
						LIGHTPAD_EXECUTABLE, LIGHTPAD_BG_ARG, cached_bg_path);
				return false;
			}

			return true;
		}

		/**
		 * Blur the cached background image in place.
		 * Prefers ImageMagick for a true Gaussian blur; falls back to a
		 * GDK pixbuf scale-down/up approximation when convert is unavailable.
		 */
		private void blur_cached_background() {
			if (imagemagick_cmd != null) {
				blur_with_imagemagick();
			} else {
				blur_with_pixbuf();
			}
		}

		/**
		 * Gaussian blur via ImageMagick convert.
		 * Overwrites cached_bg_path in place; JPEG input/output is safe.
		 */
		private void blur_with_imagemagick() {
			try {
				int exit_status;
				GLib.Process.spawn_sync(
					null,
					{ imagemagick_cmd, cached_bg_path, "-blur", IMAGEMAGICK_BLUR_PARAM, cached_bg_path },
					null,
					GLib.SpawnFlags.SEARCH_PATH,
					null, null, null,
					out exit_status
				);
				if (exit_status != 0) {
					warning("%s returned non-zero status while blurring background",
							imagemagick_cmd);
				}
			} catch (Error e) {
				warning("ImageMagick blur failed: %s", e.message);
			}
		}

		/**
		 * Approximate blur using GdkPixbuf: scale down by PIXBUF_BLUR_DIVISOR
		 * then scale back to full size.  Bilinear interpolation in both passes
		 * smooths out detail convincingly without any external dependencies.
		 */
		private void blur_with_pixbuf() {
			try {
				var original = new Gdk.Pixbuf.from_file(cached_bg_path);
				int w = original.get_width();
				int h = original.get_height();

				var small = original.scale_simple(
					int.max(1, w / PIXBUF_BLUR_DIVISOR),
					int.max(1, h / PIXBUF_BLUR_DIVISOR),
					Gdk.InterpType.BILINEAR
				);
				var blurred = small.scale_simple(w, h, Gdk.InterpType.BILINEAR);

				blurred.save(cached_bg_path, "jpeg", null, "quality", PIXBUF_JPEG_QUALITY);
			} catch (Error e) {
				warning("Pixbuf blur failed: %s", e.message);
			}
		}
	}
}


/* ---------------------------------------------------------------------- */
/* Peas module registration                                                */
/* ---------------------------------------------------------------------- */

[ModuleInit]
public void peas_register_types(TypeModule module) {
	var objmodule = module as Peas.ObjectModule;
	objmodule.register_extension_type(
		typeof(Budgie.Plugin),
		typeof(LightpadApplet.Plugin)
	);
}
