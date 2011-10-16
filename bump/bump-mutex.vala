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
  public class Mutex : GLib.Object {
    private class Data : GLib.Object {
      public Mutex? owner;
      public int priority;
      public int age;
      public GLib.Cancellable? cancellable;
      public GLib.SourceFunc? func = null;

      /**
       * Trigger the callback
       *
       * @return whether to requeue the data
       */
      public bool trigger () {
        return this.func ();
      }

      public Data (int age, int priority, GLib.Cancellable? cancellable) {
        this.age = age;
        this.priority = priority;
        this.cancellable = cancellable;
      }

      public static int compare (Mutex.Data? a, Mutex.Data? b) {
        int res = a.priority - b.priority;
        return (res != 0) ? res : a.age - b.age;
      }
    }

    /**
     * Number of items that have been added to the queue
     *
     * This is used to make sure operations with the same priority are
     * executed in the order received
     */
    private int _age = 0;

    /**
     * Atomically increment the age, returning the old value
     */
    private int increment_age () {
      return GLib.AtomicInt.exchange_and_add (ref this._age, 1);
    }

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
    public GLib.TimeSpan background_thread_timeout { get; construct; default = GLib.TimeSpan.SECOND; }

    /**
     * Lock requests which need processing
     */
    private AsyncPriorityQueue<Mutex.Data> queue = new AsyncPriorityQueue<Mutex.Data> (Mutex.Data.compare);

    /**
     * Thread to process the queue
     */
    private unowned GLib.Thread<void*>? queue_processor = null;

    /**
     * The actual lock
     */
    private GLib.Mutex inner_lock = new GLib.Mutex ();

    /**
     * The number of lock requests currently queued
     *
     * Please keep in mind that, in multi-threaded code, this value
     * may have changed by the time you see it.
     */
    public int queue_length {
      get {
        return this.queue.size;
      }
    }

    /**
     * Remove data from the queue
     *
     * @return true on success, false on failure
     */
    private bool unqueue (Mutex.Data data) {
      return this.queue.remove (data);
    }

    public void* process_queue () {
      GLib.TimeSpan background_thread_timeout = this.background_thread_timeout;
      bool finished = false;
      Mutex.Data? data = null;

      while ( !finished ) {
        /* We can't just use poll since there would be a race
         * condition between the poll and locking the inner lock, and
         * we don't want to lock the queue for a blocking poll_timed
         * request. */
        if ( this.queue.peek_timed (background_thread_timeout) != null ) {
          lock ( this.queue ) {
            this.inner_lock.lock ();
            if ( (data = this.queue.try_poll ()) == null ) {
              /* Should only happen if the request is cancelled
               * between the peek and poll, and there are no other
               * pending requests */
              this.inner_lock.unlock ();
              continue;
            }
          }

          if ( data.trigger () ) {
            data.age = this.increment_age ();
            this.queue.offer (data);
          }

          data = null;
        } else {
          lock ( this.queue ) {
            if ( this.queue_length == 0 ) {
              finished = true;
            }
          }
        }
      }

      this.queue_processor = null;
      this.unref ();

      return null;
    }

    private void connect_cancellable (Mutex.Data data) {
      if ( data.cancellable != null ) {
        data.cancellable.connect (() => {
            this.unqueue (data);
          });
      }
    }

    /**
     * Add data to the queue
     *
     * @param data the data to add to the queue
     */
    private void enqueue (Mutex.Data data) {
      if ( data.cancellable != null ) {
        this.connect_cancellable (data);
      }

      if ( data.cancellable == null ||
           !data.cancellable.is_cancelled () ) {
        data.owner = this;
        this.queue.offer (data);

        if ( this.queue_processor == null ) {
          lock ( this.queue ) {
            if ( this.queue_processor == null ) {
              try {
                this.ref ();
                this.queue_processor = GLib.Thread.create<void*> (this.process_queue, false);
              } catch ( GLib.ThreadError e ) {
                GLib.critical ("Unable to spawn queue processor: %s", e.message);
              }
            }
          }
        }
      }
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

      // Assumes GMutex is non-recursive... this may not always be the
      // case. We should check in the configure script.

      GLib.Mutex data_mutex = new GLib.Mutex ();
      Mutex.Data data = new Mutex.Data (this.increment_age (), priority, cancellable);

      data_mutex.lock ();
      data.func = () => {
        data_mutex.unlock ();

        return false;
      };
      this.enqueue (data);
      data_mutex.lock ();
    }

    /**
     * Attempt to acquire the lock without waiting
     *
     * @return true on success, false if the lock is already held.
     */
    public bool try_lock () {
      if ( this.queue_length == 0 ) {
        lock ( this.queue ) {
          if ( this.queue_length == 0 ) {
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
      GLib.return_if_fail (!this.inner_lock.trylock ());
      this.inner_lock.unlock ();
    }

    /**
     * Execute a callback and return the result
     *
     * This function will block until the lock is acquired, execute
     * the callback, then release the lock.
     *
     * @param func the callback to execute
     * @param prioriry the priority
     * @param cancellable an optional cancellable
     * @return the return value of the callback
     */
    public G execute<G> (GLib.ThreadFunc<G> func, int priority = GLib.Priority.DEFAULT, GLib.Cancellable? cancellable = null) throws GLib.Error {
      this.lock (priority, cancellable);

      try {
        return func ();
      } finally {
        this.unlock ();
      }
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
     * Add an idle callback
     *
     * The callback function will be executed in the main loop as an
     * idle callback, pausing for higher-priority tasks, until it
     * returns false (or is cancelled).
     */
    public void add_idle (owned GLib.SourceFunc func, int idle_priority = GLib.Priority.DEFAULT_IDLE, int priority = GLib.Priority.DEFAULT_IDLE) {
      this.add_background (() => {
          uint source_id = 0;
          bool res = false;
          GLib.Mutex mutex = new GLib.Mutex ();
          GLib.Cond cond = new GLib.Cond ();

          mutex.lock ();

          source_id = GLib.Idle.add_full (priority, () => {
              mutex.lock ();
              res = func ();
              cond.signal ();
              mutex.unlock ();

              return false;
            });

          return res;
        }, priority);
    }

    /**
     * Add an idle callback to be executed in another thread
     *
     * The callback function will be executed in a background thread,
     * pausing for higher-priority tasks, until it returns false.
     */
    public void add_background (owned GLib.SourceFunc func, int priority = GLib.Priority.DEFAULT_IDLE) {
      Mutex.Data data = new Mutex.Data (this.increment_age (), priority, null);
      data.func = () => {
        try {
          return func ();
        } finally {
          this.unlock ();
        }
      };
      this.enqueue (data);
    }

    /**
     * Lock the mutex asynchronously
     *
     * @param priority the priority
     * @param cancellable optional cancellable
     */
    public async void lock_async (int priority = GLib.Priority.DEFAULT, GLib.Cancellable? cancellable = null) throws GLib.Error {
      if ( cancellable != null )
        cancellable.set_error_if_cancelled ();

      bool acquired = false;
      Mutex.Data data = new Mutex.Data (this.increment_age (), priority, cancellable);
      data.func = () => {
        acquired = true;
        GLib.Idle.add (this.lock_async.callback);
        return false;
      };
      this.enqueue (data);
      yield;

      if ( !acquired ) {
        GLib.assert (cancellable != null);
        cancellable.set_error_if_cancelled ();
        GLib.assert_not_reached ();
      }
    }

    /**
     * Execute a callback asynchronously and return the result
     *
     * @param func the callback to execute
     * @param prioriry the priority
     * @param cancellable an optional cancellable
     * @return the return value of the callback, or null if cancelled
     */
    public async G? execute_async<G> (owned GLib.ThreadFunc<G> func, int priority = GLib.Priority.DEFAULT, GLib.Cancellable? cancellable = null) throws GLib.Error {
      yield this.lock_async (priority, cancellable);
      try {
        return func ();
      } finally {
        this.unlock ();
      }
    }
  }
}

#if TUMBLER_TEST_MUTEX

Tumbler.Mutex m;
GLib.MainLoop loop;

private async void test_async () {
  try {
    // Should output: Hello One Two World Three Four

    yield m.lock_async ();
    m.execute_async<void*> (() => { GLib.debug ("World"); return null; }, GLib.Priority.DEFAULT, null);
    m.execute_async<void*> (() => { GLib.debug ("Hello"); return null; }, GLib.Priority.HIGH, null);
    m.execute_async<void*> (() => {
        loop.quit ();
      return null;
      }, GLib.Priority.LOW);
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
  m = new Tumbler.Mutex ();

  GLib.debug ("Testing async...");

  test_async.begin ();
  loop.run ();

  GLib.debug ("Done... Testing background tasks...");

  int i = 0;
  GLib.Mutex m2 = new GLib.Mutex ();
  m2.lock ();
  m.add_background (() => {
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

  GLib.debug ("Done... Making sure a new background thread is created automatically...");

  GLib.Thread.usleep ((ulong) GLib.TimeSpan.SECOND * 5); // Let the old one die...
  m2.lock ();
  m.add_background (() => {
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
