# Note: plugindir is set in configure

##############################################################################
# TODO: change libgstplugin.la to something else, e.g. libmysomething.la     #
##############################################################################
plugin_LTLIBRARIES = libgstscreencapturesrc.la

##############################################################################
# TODO: for the next set of variables, name the prefix if you named the .la, #
#  e.g. libmysomething.la => libmysomething_la_SOURCES                       #
#                            libmysomething_la_CFLAGS                        #
#                            libmysomething_la_LIBADD                        #
#                            libmysomething_la_LDFLAGS                       #
##############################################################################

# sources used to compile this plug-in
libgstscreencapturesrc_la_SOURCES = plugin.m gstscreencapturesrc.m gstscreencapturesrc.h

# compiler and linker flags used to compile this plugin, set in configure.ac
libgstscreencapturesrc_la_CFLAGS =                    \
        $(GST_CFLAGS)                           \
        $(GST_BASE_CFLAGS)                      \
        $(GST_PLUGINS_BASE_CFLAGS)

libgstscreencapturesrc_la_OBJCFLAGS =                 \
        $(GST_CFLAGS)                           \
        $(GST_BASE_CFLAGS)                      \
        $(GST_PLUGINS_BASE_CFLAGS)

libgstscreencapturesrc_la_LIBADD =                    \
        $(GST_BASE_LIBS)                        \
        $(GST_PLUGINS_BASE_LIBS)                \
        -lgstinterfaces-$(GST_MAJORMINOR)       \
        -lgstvideo-$(GST_MAJORMINOR)

libgstscreencapturesrc_la_LIBTOOLFLAGS = --tag=disable-static

libgstscreencapturesrc_la_LDFLAGS =                   \
        $(GST_PLUGIN_LDFLAGS)                   \
        $(GST_BASE_LDFLAGS)                     \
        $(GST_PLUGINS_BASE_LDFLAGS)             \
        -Wl,-framework -Wl,CoreFoundation       \
        -Wl,-framework -Wl,CoreVideo            \
        -Wl,-framework -Wl,Cocoa


# headers we need but don't want installed
noinst_HEADERS = gstscreencapturesrc.h
