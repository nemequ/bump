namespace Bump {
  /**
   * A high-level non-recursive mutex
   *
   * This is a mutex designed for asynchronous GObject programming. It
   * integrates well with the main event loop and provides features
   * such as prioritization, cancellation, and asynchronous
   * interfaces. Requests with higher priorities will always be
   * executed first.
   *
   * Unfortunately, this is relatively slow compared to lower level
   * mutex implementations such as GMutex and pthreads. If you don't
   * require the advanced features, or if you only need short-lived
   * locks, it would probably be much better to use GMutex.  However,
   * if you are writing an asynchronous GObject-based application the
   * convenience provided by these methods can go a long way towards
   * helping you write applications don't block the main loop and,
   * therefore, feel faster.
   *
   * Please keep in mind that callbacks are run atomically; cancelling
   * a request will not stop a callback which is already being run.
   */
  public class Mutex : TaskQueue {
    /**
     * Number of microseconds for the background thread to wait for data
     *
     * If this number is exceeded the background thread will exit and
     * a new one will be created when data is added to the queue. A
     * negative value will cause the background thread to exist
     * indefinitely, and 0 will cause the background thread to exit
     * immediately when the last queued lock request is fulfilled.
     *
     * The default value is one second.
     */
    public GLib.TimeSpan max_idle_time { get; construct; default = GLib.TimeSpan.SECOND; }

    /**
     * Thread to process the queue
     */
    private unowned GLib.Thread<void*>? processor = null;

    /**
     * The actual lock
     */
    private GLib.Mutex inner_lock = new GLib.Mutex ();

    private unowned AsyncPriorityQueue<TaskQueue.Data> queue;

    private void* process_cb () {
      GLib.TimeSpan max_idle_time = this.max_idle_time;
      bool finished = false;
      TaskQueue.Data? data = null;

      while ( !finished ) {
        /* We can't just use poll since there would be a race
         * condition between the poll and locking the inner lock, and
         * we don't want to lock the queue for a blocking poll_timed
         * request. */
        if ( this.queue.peek_timed (max_idle_time) != null ) {
          this.inner_lock.lock ();
          if ( (data = this.queue.try_poll ()) == null ) {
            /* Should only happen if the request is cancelled
             * between the peek and poll, and there are no other
             * pending requests */
            this.inner_lock.unlock ();
            continue;
          }

          if ( data.trigger () ) {
            this.add_internal (data);
          }

          data = null;
        } else {
          lock ( this.queue ) {
            if ( this.length == 0 ) {
              finished = true;
            }
          }
        }
      }

      this.processor = null;

      return null;
    }

    /**
     * Executes the callback but does not unlock the mutex upon
     * completion
     *
     * This is necessary for the {@link lock} and {@link unlock}
     * methods, but we don't want to make {@link add} do this since it
     * is public.
     */
    private void add_without_unlock (owned GLib.SourceFunc task, int priority = GLib.Priority.DEFAULT, GLib.Cancellable? cancellable = null) throws GLib.Error {
      lock ( this.queue ) {
        base.add (() => {
            return task ();
          }, priority, cancellable);
      }

      if ( this.processor == null ) {
        lock ( this.processor ) {
          if ( this.processor == null ) {
            this.processor = GLib.Thread.create<void*> (this.process_cb, false);
          }
        }
      }
    }

    public override void add (owned GLib.SourceFunc task, int priority = GLib.Priority.DEFAULT, GLib.Cancellable? cancellable = null) throws GLib.Error {
      this.add_without_unlock (() => {
            try {
              return task ();
            } finally {
              this.unlock ();
            }
        }, priority, cancellable);
    }

    /**
     * Acquire the lock
     */
    public void lock (int priority = GLib.Priority.DEFAULT, GLib.Cancellable? cancellable = null) throws GLib.Error {
      if ( cancellable != null )
        cancellable.set_error_if_cancelled ();

      if ( this.try_lock () ) {
        return;
      }

      bool acquired = false;

      // Assumes GMutex is non-recursive... this may not always be the
      // case. We should check in the configure script.

      GLib.Mutex data_mutex = new GLib.Mutex ();
      data_mutex.lock ();
      this.add_without_unlock (() => {
          acquired = true;
          data_mutex.unlock ();

          return false;
        }, priority, cancellable);
      data_mutex.lock ();

      if ( !acquired ) {
        GLib.assert (cancellable != null);
        cancellable.set_error_if_cancelled ();
        GLib.assert_not_reached ();
      }
    }

    /**
     * Attempt to acquire the lock without waiting
     *
     * @return true on success, false if the lock is already held.
     */
    public bool try_lock () {
      if ( this.length == 0 ) {
        lock ( this.queue ) {
          if ( this.length == 0 ) {
            return this.inner_lock.trylock ();
          }
        }
      }

      return false;
    }

    /**
     * Release the lock.
     */
    public void unlock () {
#if BUMP_DEBUG
      GLib.assert (!this.inner_lock.trylock ());
#endif
      this.inner_lock.unlock ();
    }

    /**
     * Attempt to execute a callback without blocking
     *
     * This function will try to acquire the lock and, if successful,
     * execute the callback.
     *
     * @param func the callback
     * @return the return value of the callback, or null if it would have blocked
     */
    public G? try_execute<G> (GLib.ThreadFunc<G> func) throws GLib.Error {
      if ( this.try_lock () ) {
        try {
          return func ();
        } finally {
          this.unlock ();
        }
      } else {
        return null;
      }
    }

    /**
     * Lock the mutex asynchronously
     *
     * @param priority the priority
     * @param cancellable optional cancellable
     */
    public async void lock_async (int priority = GLib.Priority.DEFAULT, GLib.Cancellable? cancellable = null) throws GLib.Error {
      bool acquired = false;
      this.add_without_unlock (() => {
          acquired = true;
          GLib.Idle.add (this.lock_async.callback);
          return false;
        }, priority, cancellable);
      yield;

      if ( !acquired ) {
        GLib.assert (cancellable != null);
        cancellable.set_error_if_cancelled ();
        GLib.assert_not_reached ();
      }
    }

    public override G execute<G> (GLib.ThreadFunc<G> func, int priority = GLib.Priority.DEFAULT, GLib.Cancellable? cancellable = null) throws GLib.Error {
      this.lock (priority, cancellable);
      try {
        return func ();
      } finally {
        this.unlock ();
      }
    }

    public override async G execute_async<G> (GLib.ThreadFunc<G> func, int priority = GLib.Priority.DEFAULT, GLib.Cancellable? cancellable = null) throws GLib.Error {
      yield this.lock_async (priority, cancellable);
      try {
        return func ();
      } finally {
        this.unlock ();
      }
    }

    /**
     * Claim the lock
     *
     * @param priority the priority
     * @param cancellable optional cancellable
     */
    public Claim claim (int priority = GLib.Priority.DEFAULT, GLib.Cancellable? cancellable = null) throws GLib.Error {
      Claim claim = new Claim (this);
      claim.init (cancellable);
      return claim;
    }

    /**
     * Claim the lock asynchronously
     *
     * @param priority the priority
     * @param cancellable optional cancellable
     */
    public async Claim claim_async (int priority = GLib.Priority.DEFAULT, GLib.Cancellable? cancellable = null) throws GLib.Error {
      Claim claim = new Claim (this);
      yield claim.init_async (priority, cancellable);
      return claim;
    }

    construct {
      this.queue = this.get_queue ();
    }
  }
}

#if BUMP_TEST_MUTEX

Bump.Mutex m;
GLib.MainLoop loop;

private async void test_async () {
  try {
    // Should output: Hello One Two World Three Four

    yield m.lock_async ();
    GLib.debug ("One");
    m.execute_async<void*> (() => { GLib.debug ("World"); return null; }, GLib.Priority.DEFAULT, null);
    GLib.debug ("Two");
    m.execute_async<void*> (() => { GLib.debug ("Hello"); return null; }, GLib.Priority.HIGH, null);
    GLib.debug ("Three");
    m.execute_async<void*> (() => {
        loop.quit ();
      return null;
      }, GLib.Priority.LOW);
    GLib.debug ("Opening the flood gate");
    m.unlock ();

    yield m.execute_async<void*> (() => { GLib.debug ("One"); return null; }, GLib.Priority.HIGH);
    GLib.debug ("Two");
    yield m.execute_async<void*> (() => { GLib.debug ("Three"); return null; }, GLib.Priority.DEFAULT);
    GLib.debug ("Four");
  } catch ( GLib.Error e ) {
    GLib.error (e.message);
  }
}

private static int main (string[] args) {
  loop = new GLib.MainLoop ();
  m = new Bump.Mutex ();

  GLib.debug ("Testing async...");

  test_async.begin ();
  loop.run ();

  GLib.debug ("Done... Testing background tasks...");

  int i = 0;
  GLib.Mutex m2 = new GLib.Mutex ();
  m2.lock ();
  m.add (() => {
      if ( i < 8 ) {
        GLib.debug ("%d", ++i);
        return true;
      } else {
        m2.unlock ();
        return false;
      }
    });
  m2.lock ();
  m2.unlock ();

  GLib.debug ("Done...");

  GLib.Thread.usleep ((ulong) GLib.TimeSpan.SECOND * 2); // Let the old one die...
  GLib.debug ("Making sure a new background thread is created automatically...");

  m2.lock ();
  m.add (() => {
      if ( i < 12 ) {
        GLib.debug ("%d", ++i);
        return true;
      } else {
        m2.unlock ();
        return false;
      }
    });
  m2.lock ();

  GLib.debug ("Done");

  return 0;
}

#endif
