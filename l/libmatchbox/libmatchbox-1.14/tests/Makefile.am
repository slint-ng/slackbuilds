SUBDIRS = menu

AM_CPPFLAGS = @CHECK_CFLAGS@ -I$(top_srcdir) -I$(top_builddir) @GCC_WARNINGS@ @XLIBS_CFLAGS@ @PANGO_CFLAGS@ @PNG_CFLAGS@
AM_LDFLAGS = ../libmb/libmb.la @XLIBS_LIBS@

if HAVE_CHECK

TESTS = dot-desktop pixbuf unicode

check_PROGRAMS=dot-desktop pixbuf unicode

dot_desktop_SOURCES=dot-desktop.c
dot_desktop_LDADD= @CHECK_LIBS@

pixbuf_SOURCES=pixbuf.c oh.h
pixbuf_LDADD= @CHECK_LIBS@

unicode_SOURCES=unicode.c
unicode_LDADD= @CHECK_LIBS@

else

TESTS =

endif

noinst_PROGRAMS = dump-image
dump_image_SOURCES=dump-image.c

EXTRA_DIST = oh-overlayed.png oh.png oh-scaled.png overlay.png oh.jpg oh.xpm \
             dot-desktop.c pixbuf.c oh.h

-include $(top_srcdir)/git.mk
