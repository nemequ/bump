#                                               -*- Autoconf -*-
# Process this file with autoconf to produce a configure script.

m4_define([bump_major], [0])
m4_define([bump_minor], [0])
m4_define([bump_micro], [1])

m4_define([bump_version], [bump_major.bump_minor.bump_micro])
m4_define([bump_api_version], [0.1])

m4_define([bump_name], [bump])

AC_PREREQ([2.64])
AC_INIT([Bump], [bump_version], [evan@coeus-group.com]. [bump_name])
AC_CONFIG_HEADERS([bump/config.h])
AC_CONFIG_MACRO_DIR([m4])
AM_INIT_AUTOMAKE([dist-bzip2])
AM_MAINTAINER_MODE

BUMP_MAJOR_VERSION=bump_major
BUMP_MINOR_VERSION=bump_minor
BUMP_MICRO_VERSION=bump_micro
BUMP_VERSION=bump_version
BUMP_API_VERSION=bump_api_version
AC_SUBST(BUMP_MAJOR_VERSION)
AC_SUBST(BUMP_MINOR_VERSION)
AC_SUBST(BUMP_MICRO_VERSION)
AC_SUBST(BUMP_VERSION)
AC_SUBST(BUMP_API_VERSION)

m4_ifdef([AM_SILENT_RULES],[AM_SILENT_RULES([yes])])

VALA_REQUIRED=0.14.0.37
GLIB_REQUIRED=2.22.0
GEE_REQUIRED=0.6

# Checks for programs.
AC_PROG_CC
AM_PROG_CC_C_O
AC_PROG_INSTALL
AC_PROG_LIBTOOL
AM_PROG_VALAC($VALA_REQUIRED)

GOBJECT_INTROSPECTION_CHECK([0.10])
AM_CONDITIONAL(HAVE_INTROSPECTION, false)

# Checks for libraries.
PKG_CHECK_MODULES(GIO, gio-2.0 >= $GLIB_REQUIRED)
AC_SUBST(GIO_CFLAGS)
AC_SUBST(GIO_LIBS)
PKG_CHECK_MODULES(GLIB, glib-2.0 >= $GLIB_REQUIRED)
GLIB_VERSION=$($PKG_CONFIG --modversion glib-2.0)
AC_SUBST(GLIB_VERSION)
AC_SUBST(GLIB_CFLAGS)
AC_SUBST(GLIB_LIBS)
PKG_CHECK_MODULES(GOBJECT, gobject-2.0 >= $GLIB_REQUIRED)
AC_SUBST(GOBJECT_CFLAGS)
AC_SUBST(GOBJECT_LIBS)
PKG_CHECK_MODULES(GEE, gee-1.0 >= $GEE_REQUIRED)
AC_SUBST(GEE_CFLAGS)
AC_SUBST(GEE_LIBS)

AC_ARG_ENABLE(valadoc,
  AS_HELP_STRING([--enable-valadoc[=@<:@no/auto/yes@:>@]], [Enable valadoc support]),,
    [enable_valadoc=auto])

found_valadoc=no
AS_IF([test "x$enable_valadoc" != "xno"], [
    AC_PATH_PROG(VALADOC, valadoc, :)
    AS_IF([test -x "$VALADOC"], [
      found_valadoc=yes
      AC_SUBST(VALADOC)
    ], [
      AS_IF([test "x$enable_valadoc" == "xyes"], AC_MSG_ERROR([Unable to find valadoc]))
    ])
  ])

AM_CONDITIONAL(ENABLE_VALADOC, test x$found_valadoc = xyes)

# Checks for header files.
AC_CHECK_HEADERS([stdlib.h string.h])

# Checks for typedefs, structures, and compiler characteristics.

# Checks for library functions.

AC_CONFIG_FILES([Makefile
                 bump/Makefile
                 bump.pc])
AC_OUTPUT
