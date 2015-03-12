# File Locking #

It wouldn't be difficult to do it with fcntl, but that probably will only work for POSIX. Unfortunately priority (and FIFO for the same priority) would only work within a single process, unless there was some sort of IPC (which could be added to a second, higher level class a bit later on).

Perhaps we should add basic file locking support to GLib, with back-ends for (at least) fcntl and whatever Windows uses?

# Background Worker #

I started working on this, and there is a [Bump.Worker](http://code.google.com/p/bump/source/browse/bump/bump-worker.vala) class in git, but it's disabled for now since I'm still trying to figure out the API.

# Reader-Writer Lock #

GLib has one ([GRWLock](http://developer.gnome.org/glib/stable/glib-Threads.html#GRWLock)) if you're not familiar with the idea. Java has one ([ReadWriteLock](http://docs.oracle.com/javase/1.5.0/docs/api/java/util/concurrent/locks/ReadWriteLock.html) in java.util.concurrent.locks). So does .NET ([System.Threading.ReaderWriterLockSlim](http://msdn.microsoft.com/en-us/library/system.threading.readerwriterlockslim.aspx)).

It should probably be a Semaphore subclass with `execute*`, `lock*`, and `claim*` variants for acquiring the write lock.

# Shared buffers with reader-writer range locks #

Useful for sharing buffers across multiple data structures and threads.  It might be possible to use GBytes (by creating it with a custom free function that also unlocks the source), so we could have GLib.Bytes get\_range (int offset, int length) which would return a (reader-locked) read-only reference to the requested range, and get\_writable\_range would return a (writer-locked) R/W reference.

It should also be possible to use this with mmaped buffers.

It may also be a good idea to add a signal for when a writable lock is released to use for change notification.

# ??? #

Ideas welcome.