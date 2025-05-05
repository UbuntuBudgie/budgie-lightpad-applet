project(
  'budgie_lightpad',
  'vala', 'c',
  version : '0.0.3',
  default_options: [
        'c_std=c11',
        'warning_level=3'
    ],
)

# Vala generates bad C code and missing these on gcc 14 will cause FTBFS
# Additionally, Meson 1.4 unhides warnings from valac-generated C code,
# which causes unreadable logspam. Reenables prior behavior.
am_cflags = [
    '-w',
    '-Wno-incompatible-pointer-types',
    '-Wno-implicit-function-declaration',
]
add_global_arguments(am_cflags, language: 'c')


gnome = import('gnome')

prefix = get_option('prefix')
datadir = join_paths(prefix, get_option('datadir'))
libdir = join_paths(prefix, get_option('libdir'))

glib_dep = dependency('glib-2.0')
gio_dep = dependency('gio-2.0')
gtk_dep = dependency('gtk+-3.0')
gobject_dep = dependency('gobject-2.0')
gio_unix_dep = dependency('gio-unix-2.0')
budgie_dep = dependency('budgie-2.0')
peas_dep = dependency('libpeas-gtk-1.0')

subdir('src')
