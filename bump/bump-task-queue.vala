namespace Bump {
  /**
   * Callback which is invoked by the {@link TaskQueue.execute} and
   * {@link TaskQueue.execute_async} functions.
   *
   * This is similar to GThreadFunc, except the delegate can throw
   * exceptions.
   */
  public delegate G Callback<G> () throws GLib.Error;

  /**
   * Base class used for common task queueing behavior
   */
  public class TaskQueue : GLib.Object {
    internal class Data : CallbackQueue.Data {
      public GLib.SourceFunc? task;

      /**
       * Trigger the callback
       *
       * @return whether to requeue the data
       */
      public bool trigger () {
        return this.task ();
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
     * Requests which need processing
     */
    private Bump.CallbackQueue<Bump.TaskQueue.Data> queue =
      new Bump.CallbackQueue<Bump.TaskQueue.Data> ();

    internal unowned Bump.CallbackQueue<TaskQueue.Data> get_queue () {
      return this.queue;
    }

    /**
     * The number of requests currently queued
     *
     * Please keep in mind that in multi-threaded code this value may
     * have changed by the time you see it.
     */
    public int length {
      get {
        return this.queue.length;
      }
    }

    internal void remove (TaskQueue.Data data) {
      this.queue.remove (data);
      data.cancellable.disconnect (data.cancellable_id);
    }

    /**
     * Create a new data structure
     *
     * @param priority the priority of the callback
     * @param cancellable optional cancellable
     */
    private Bump.TaskQueue.Data prepare (int priority = GLib.Priority.DEFAULT, GLib.Cancellable? cancellable = null) throws GLib.Error {
      Bump.TaskQueue.Data data = new Bump.TaskQueue.Data ();
      data.priority = priority;
      data.cancellable = cancellable;

      return data;
    }

    /**
     * Add a task to the queue
     *
     * @param task the task
     * @param priority the priority of the task
     * @param cancellable optional cancellable for aborting the task
     */
    public virtual void add (owned GLib.SourceFunc task, int priority = GLib.Priority.DEFAULT, GLib.Cancellable? cancellable = null) throws GLib.Error {
      TaskQueue.Data data = this.prepare (priority, cancellable);new TaskQueue.Data ();
      data.task = () => { return task (); };
      this.queue.offer (data);
    }

    /**
     * Process a single task in the queue
     *
     * This is method should not usually be called by user code (which
     * should usually be calling {@link execute} instead). This method
     * will naïvely invoke the callback and remove or requeue it
     * depending on the result, and assumes that any locks have
     * already been acquired.
     *
     * @param wait the maximum number of microseconds to wait for an
     *   item to appear in the queue (0 for no waiting, < 0 to wait
     *   indefinitely).
     * @return true if an item was processed, false if not
     */
    public virtual bool process (GLib.TimeSpan wait = 0) {
      TaskQueue.Data? data = this.queue.poll_timed (wait);

      if ( data != null ) {
        if ( data.trigger () ) {
          data.age = this.increment_age ();
          this.queue.offer (data);
        } else {
          data.owner = null;
        }

        return true;
      } else {
        return false;
      }
    }

    private class ThreadCallbackData<G> {
      public G? return_value;
      public Callback<G> thread_func;
      public GLib.Error error;

      public bool source_func () {
        try {
          this.return_value = thread_func ();
        } catch ( GLib.Error e ) {
          this.error = e;
        }

        return false;
      }
    } 

    /**
     * Execute a callback, blocking until it is done
     *
     * @param func the callback to execute
     * @param priority the priority
     * @param cancellable optional cancellable for aborting the
     *   operation
     */
    public virtual G execute<G> (Callback<G> func, int priority = GLib.Priority.DEFAULT, GLib.Cancellable? cancellable = null) throws GLib.Error {
      GLib.Mutex mutex = new GLib.Mutex ();
      ThreadCallbackData<G> data = new ThreadCallbackData<G> ();

      data.thread_func = () => {
        try {
          return func ();
        } finally {
          mutex.unlock ();
        }
      };

      mutex.lock ();
      this.add (data.source_func, priority, cancellable);
      mutex.lock ();

      if ( data.error != null ) {
        throw data.error;
      }

      return data.return_value;
    }

    /**
     * Execute a callback asynchronously
     *
     * @param func the callback to execute
     * @param priority the priority
     * @param cancellable optional cancellable for aborting the
     *   operation
     */
    public virtual async G execute_async<G> (Callback<G> func, int priority = GLib.Priority.DEFAULT, GLib.Cancellable? cancellable = null) throws GLib.Error {
      ThreadCallbackData<G> data = new ThreadCallbackData<G> ();

      data.thread_func = () => {
        try {
          return func ();
        } finally {
          GLib.Idle.add (this.execute_async.callback);
        }
      };
      this.add (data.source_func, priority, cancellable);
      yield;

      if ( data.error != null ) {
        throw data.error;
      }

      return data.return_value;
    }
  }
}

#if BUMP_TEST_TASK_QUEUE
private static int main (string[] args) {
  var q = new Bump.TaskQueue ();
  q.add (() => { GLib.debug ("One"); return false; });
  q.add (() => { GLib.debug ("Two"); return false; });
  q.add (() => { GLib.debug ("Three"); return false; });

  int i = 0;
  q.add (() => {
      GLib.debug (":: %d", ++i);
      return i < 8;
    }, GLib.Priority.HIGH);

  while ( q.process (GLib.TimeSpan.SECOND) ) {
    GLib.debug ("Processed");
  }

  GLib.Thread.create<void*> (() => {
      while ( q.process (GLib.TimeSpan.SECOND) ) { }

      return null;
    }, false);

  try {
    GLib.critical ("Failed to catch an error: %s", q.execute<string> (() => {
          throw new GLib.IOError.FAILED ("Error thrown from callback");
          return "Should not be reached.";
        }));
  } catch ( GLib.Error e ) {
    GLib.debug ("Caught an error (as expected): %s", e.message);
  }

  GLib.MainLoop loop = new GLib.MainLoop ();

  q.execute_async<string> (() => {
      GLib.debug (":)");

      return "Processed asynchronously.";
    }, GLib.Priority.DEFAULT, null, (obj, async_res) => {
      // https://bugzilla.gnome.org/show_bug.cgi?id=661961
      // GLib.debug (q.execute_async.end (async_res));
      GLib.debug ("Processed asynchronously.");
    });

  GLib.Idle.add (() => {
      if ( q.process (GLib.TimeSpan.SECOND) ) {
        GLib.debug ("Processed (in idle)");
        return true;
      } else {
        GLib.debug ("Timeout");
        loop.quit ();
        return false;
      }
    });

  loop.run ();

  return 0;
}
#endif
