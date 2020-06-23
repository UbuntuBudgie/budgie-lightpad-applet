# BudgieLightpad Applet

Lightweight and stylish fullscreen application launcher.

![Screenshot](data/screenshot.png?raw=true)

This provides the applet to launch https://github.com/libredeb/lightpad.
This project is a prerequisite.


## Building and Installation

You'll need the following dependencies:
* libgtk-3-dev
* budgie-core-dev
* libpeas-dev
* meson
* valac

Run `meson` to configure the build environment and then `ninja` to build

    meson build --prefix=/usr --libdir=/usr/lib
    cd build
    ninja

To install, use `ninja install`

    sudo ninja install
