namespace Bump {
  /**
   * A pool of threads
   *
   * This is somewhat similar to GThreadPool from GLib, except that it
   * uses async methods and callbacks instead of data structures and
   * supports prioritization and cancellation.
   */
  public class ThreadPool : TaskQueue {
    /**
     * The maximum number of threads to use
     *
     * For unlimited, use 0
     */
    public int max_threads { get; set; default = 0; }

    /**
     * The maximum amount of time (in microseconds) to allow a thread
     * to remain unused before removing it
     *
     * For unlimited, use < 0. For none, use 0.
     *
     * Changing this value will not have any effect on an already
     * waiting thread, though the thread will pick up the new value
     * next time it needs to wait.
     */
    public GLib.TimeSpan max_idle_time { get; set; default = GLib.TimeSpan.SECOND; }

    private int _count = 0;

    private unowned AsyncPriorityQueue<TaskQueue.Data> queue;

    /**
     * Number of threads currently in the pool
     */
    public int count {
      get {
        return this._count;
      }
    }

    /**
     * Number of threads currently idling
     */
    public int idle_count {
      get {
        return this.queue.waiting_threads;
      }
    }

    public override void add (owned GLib.SourceFunc task, int priority = GLib.Priority.DEFAULT, GLib.Cancellable? cancellable = null) throws GLib.Error {
      base.add (() => { return task (); }, priority, cancellable);

      bool spawn_new_thread = false;
      lock ( this.count ) {
        if ( (this.idle_count == 0) && ((this.max_threads == 0) || (this._count < this.max_threads)) ) {
          spawn_new_thread = true;
          this._count++;
        }
      }

      if ( spawn_new_thread ) {
        GLib.Thread.create<void*> (() => {
            while ( this.process (this.max_idle_time) ) { }

            lock ( this.count ) {
              this._count--;
            }
            return null;
          }, false);
      }
    }

    /**
     * Create a new thread pool
     */
    public ThreadPool (int max_threads = 0) {
      GLib.Object (max_threads: max_threads);
    }

    /**
     * Update the max_threads property to the new value if it permits
     * more threads than the old value.
     *
     * Setting the max_threads property can clobber the value, so you
     * should prefer to use this method if you want to increase the
     * number of threads since.
     */
    public void increase_max_threads (int new_max_threads) {
      lock ( this.max_threads ) {
        if ( (max_threads == 0 && this.max_threads > 0) || this.max_threads < max_threads ) {
          this.max_threads = max_threads;
        }
      }
    }

    construct {
      this.queue = this.get_queue ();
    }

    private static unowned ThreadPool? global_pool = null;

    /**
     * Get the global thread pool
     *
     * This will retrieve a global thread pool, creating it if it does
     * not exist.
     *
     * If either value is 0, the maximum number of threads of the
     * returned pool will be 0. Otherwise, the it will be whichever
     * value is greater.
     *
     * @param max_threads the minimum max_threads value of the thread pool
     */
    public ThreadPool get_global (int max_threads) {
      ThreadPool? gp = global_pool;

      if ( gp == null ) {
        lock ( global_pool ) {
          if ( global_pool == null ) {
            global_pool = gp = new ThreadPool (max_threads);
            gp.add_weak_pointer (&global_pool);
          } else {
            gp = global_pool;
          }
        }
      }

      gp.increase_max_threads (max_threads);

      return gp;
    }
  }
}

#if BUMP_TEST_THREAD_POOL
private static int main (string[] args) {
  var tp = new Bump.ThreadPool ();
  for ( int i = 0 ; i < 32 ; i++ ) {
    int tn = i;
    tp.add (() => {
        GLib.debug (":> %d", tn);

        return false;
      });
  }

  GLib.Thread.usleep ((long) GLib.TimeSpan.SECOND * 2);

  return 0;
}
#endif
