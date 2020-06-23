gresource = join_paths(meson.current_source_dir(), 'plugin.gresource.xml')

lightpaddir = join_paths(libdir, 'budgie-desktop', 'plugins', 'lightpad')

# Compile the assets into the binary
applet_lightpad_resources = gnome.compile_resources(
    'lightpadapplet-applet-resources',
    gresource,
    source_dir: meson.current_source_dir(),
    c_name: 'budgie_lightpadapplet',
)

sources = [
    'Lightpad.vala',
    'IconChooser.vala',
    applet_lightpad_resources
]

dependencies = [
    glib_dep,
    gobject_dep,
    gio_dep,
    gio_unix_dep,
    gtk_dep,
    budgie_dep,
    peas_dep,
]

c_args = [
]

shared_module(
    'lightpad',
    sources,
    dependencies: dependencies,
    vala_args: [],
    c_args : c_args,
    install: true,
    install_dir: lightpaddir
)

install_data('Lightpad.plugin', install_dir: lightpaddir)
