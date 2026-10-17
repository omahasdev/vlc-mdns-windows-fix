/* libmicrodns 0.2.0 configuration for x86_64-w64-mingw32, written by hand
 * from meson.build. No HAVE_POLL: VLC 3.0 targets Windows XP and uses the
 * compat poll() of libmicrodns. */
#define HAVE_INET_NTOP 1
#define HAVE_STRUCT_POLLFD 1
#define HAVE_UNISTD_H 1
