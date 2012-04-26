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
	--target-glib $(GLIB_TARGET_VERSION) \
	--vapidir $(top_builddir)/bump \
	--pkg bump-@BUMP_API_VERSION@ \
	--pkg gio-2.0

TEST_PROGS += event-test
event_test_SOURCES = event-test.vala

TEST_PROGS += task-queue-test
task_queue_test_SOURCES = task-queue-test.vala

TEST_PROGS += semaphore-test
semaphore_test_SOURCES = semaphore-test.vala

TEST_PROGS += resource-pool-test
resource_pool_test_SOURCES = resource-pool-test.vala

TEST_PROGS += claim-test
claim_test_SOURCES = claim-test.vala

TEST_PROGS += lazy-test
lazy_test_SOURCES = lazy-test.vala

GITIGNORE = \
	$(TEST_PROGS) \
	$(foreach prog,$(TEST_PROGS),$(subst /,_,$(subst -,_,$(subst .,_,$(prog))))_vala.stamp) \
	$(foreach srcs,$(foreach prog,$(TEST_PROGS),$(subst /,_,$(subst -,_,$(subst .,_,$(prog))))_SOURCES),$($(srcs):.vala=.c) $($(srcs):.vala=.o))

.gitignore: .gitignore.in
	$(AM_V_GEN) echo "# Automatically generated from $^. Do not edit." > $@ && \
	cat < $^ >> $@ && \
	for ignoredfile in $(GITIGNORE); do \
	  echo /$$ignoredfile >> $@; \
	done;

BUILT_SOURCES = .gitignore
