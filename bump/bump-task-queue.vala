namespace Bump {
  /**
   * Base class used for common task queueing behavior
   */
  public class TaskQueue : GLib.Object {
    internal class Data {
      public TaskQueue? owner;
      public int priority;
      public int age;
      public GLib.SourceFunc? task;
      public GLib.Cancellable? cancellable;
      public ulong cancellable_id;

      public void connect_cancellable () {
        if ( this.cancellable != null ) {
          if ( this.cancellable_id != 0 ) {
            this.disconnect_cancellable ();
          }

          this.cancellable_id = this.cancellable.connect ((c) => {
              this.owner.remove (this);
            });
        }
      }

      public void disconnect_cancellable () {
        if ( this.cancellable != null && this.cancellable_id != 0 ) {
          this.cancellable.disconnect (this.cancellable_id);
          this.cancellable_id = 0;
        }
      }

      /**
       * Trigger the callback
       *
       * @return whether to requeue the data
       */
      public bool trigger () {
        return this.task ();
      }

      public static int compare (TaskQueue.Data? a, TaskQueue.Data? b) {
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
     * Requests which need processing
     */
    private AsyncPriorityQueue<TaskQueue.Data> queue = new AsyncPriorityQueue<TaskQueue.Data> (TaskQueue.Data.compare);

    internal unowned AsyncPriorityQueue<TaskQueue.Data> get_queue () {
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
        return this.queue.size;
      }
    }

    internal void remove (TaskQueue.Data data) {
      this.queue.remove (data);
      data.cancellable.disconnect (data.cancellable_id);
    }

    /**
     * Add (or re-add) to queue
     */
    internal void add_internal (TaskQueue.Data data) {
      if ( data.cancellable == null || !data.cancellable.is_cancelled () ) {
        data.age = this.increment_age ();
        this.queue.offer (data);
        if ( data.cancellable_id == 0 )
          data.connect_cancellable ();
      }
    }

    /**
     * Add a task to the queue
     *
     * @param task the task
     * @param priority the priority of the task
     * @param cancellable optional cancellable for aborting the task
     */
    public virtual void add (owned GLib.SourceFunc task, int priority = GLib.Priority.DEFAULT, GLib.Cancellable? cancellable = null) throws GLib.Error {
      TaskQueue.Data data = new TaskQueue.Data ();
      data.owner = this;
      data.priority = priority;
      data.task = () => { return task (); };
      data.cancellable = cancellable;
      this.add_internal (data);
    }

    /**
     * Process a single task in the queue
     *
     * @param wait the maximum number of microseconds to wait for an
     *   item to appear in the queue
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
      public GLib.ThreadFunc<G> thread_func;

      public bool source_func () {
        this.return_value = thread_func ();

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
    public virtual G execute<G> (GLib.ThreadFunc<G> func, int priority = GLib.Priority.DEFAULT, GLib.Cancellable? cancellable = null) throws GLib.Error {
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
    public virtual async G execute_async<G> (GLib.ThreadFunc<G> func, int priority = GLib.Priority.DEFAULT, GLib.Cancellable? cancellable = null) throws GLib.Error {
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

  GLib.debug (q.execute<string> (() => { return "Processed in background."; }));

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
