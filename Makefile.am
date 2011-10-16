NULL =

SUBDIRS = \
	bump \
	$(NULL)

ACLOCAL_AMFLAGS=-I m4

bump-@BUMP_API_VERSION@.pc: bump.pc
	$(AM_V_GEN) cat < $^ > $@

pkgconfigdir = $(libdir)/pkgconfig
pkgconfig_DATA = \
	bump-@BUMP_API_VERSION@.pc \
	$(NULL)

DISTCLEANFILES = \
	bump-@BUMP_API_VERSION@.pc \
	bump.pc \
	$(NULL)

EXTRA_DIST = \
	bump.pc.in \
	$(NULL)
