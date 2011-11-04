include $(top_srcdir)/Makefile.decl

noinst_PROGRAMS = $(TEST_PROGS)

LDADD = \
	$(top_builddir)/bump/libbump@BUMP_API_VERSION@.la \
	$(GIO_LIBS) \
	$(GLIB_LIBS) \
	$(GOBJECT_LIBS) \
	$(GEE_LIBS)

AM_CFLAGS = \
	-I$(top_srcdir)/bump \
	$(GIO_CFLAGS) \
	$(GLIB_CFLAGS) \
	$(GOBJECT_CFLAGS) \
	$(GEE_CFLAGS)

VALAFLAGS = \
	--vapidir $(top_builddir)/bump \
	--pkg bump-@BUMP_API_VERSION@

TEST_PROGS += event-test
event_test_SOURCES = event-test.vala
