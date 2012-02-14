namespace Bump {
  /**
   * Callback which is invoked by the {@link TaskQueue.execute} and
   * {@link TaskQueue.execute_async} functions.
   *
   * This is similar to {@link GLib.ThreadFunc}, except the delegate
   * can throw exceptions.
   */
  public delegate G Callback<G> () throws GLib.Error;

  /**
   * Base class used for common task queueing behavior
   */
  public class TaskQueue : GLib.Object, Bump.Queue, Bump.Threading {
    internal class Data : CallbackQueue.Data {
      public GLib.SourceFunc? task;

      /**
       * Trigger the callback
       *
       * @return whether to re-queue the data
       */
      public bool process () {
        return this.task ();
      }
    }

    /**
     * Requests which need processing
     */
    private Bump.CallbackQueue<Bump.TaskQueue.Data> queue;

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
     * Spawn new threads if appropriate
     *
     * @return whether or not a new thread was created
     */
    protected virtual int spawn (int max = -1) {
      if ( max == 0 )
        return 0;
      else if ( max == -1 )
        max = this.length;
      else
        max = int.min (this.length, max);

      return this.spawn_internal (max);
    }

    /**
     * Add a task to the queue
     *
     * @param task the task
     * @param priority the priority of the task
     * @param cancellable optional cancellable for aborting the task
     */
    public virtual void add (owned GLib.SourceFunc task, int priority = GLib.Priority.DEFAULT, GLib.Cancellable? cancellable = null) throws GLib.Error {
      TaskQueue.Data data = this.prepare (priority, cancellable);
      data.task = (owned) task;
      this.queue.offer (data);
      this.spawn (-1);
    }

    public virtual bool process (GLib.TimeSpan wait = 0) {
      TaskQueue.Data? data = this.queue.poll_timed (wait);

      if ( data == null )
        return false;
      else {
        this.run_task (data.process);
        return true;
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
     * The callback will be executed in the calling thread. Note that
     * the calling thread will block until the callback can be
     * processed, so if this method is called from the default thread
     * it will block the main loop and likely lead to a deadlock. When
     * executing a callback from the default thread you should use
     * {@link execute_async} or {@link execute_background}.
     *
     * @param func the callback to execute
     * @param priority the priority
     * @param cancellable optional cancellable for aborting the
     *   operation
     */
    public virtual G execute<G> (Callback<G> func, int priority = GLib.Priority.DEFAULT, GLib.Cancellable? cancellable = null) throws GLib.Error {
      GLib.Mutex mutex = GLib.Mutex ();
      ThreadCallbackData<G> data = new ThreadCallbackData<G> ();

      mutex.lock ();
      this.add (() => {
          mutex.unlock ();
          return false;
        }, priority, cancellable);
      mutex.lock ();

      return func ();
    }

    /**
     * Execute a callback asynchronously in an idle callback
     *
     * The priority argument for this can be a bit misleading when
     * mixed with {@link execute} and {@link execute_background}. When
     * a callback is queued with this method it will be sent to the
     * main loop in order based on priority and the time it was added,
     * but when the callback is actually executed will then be
     * controlled by the GLib Main Loop. It will, however, be executed
     * in the proper order relative to any other callbacks which have
     * already been sent to the main loop.
     *
     * @param func the callback to execute
     * @param priority the priority
     * @param cancellable optional cancellable for aborting the
     *   operation
     */
    public virtual async G execute_async<G> (owned Callback<G> func, int priority = GLib.Priority.DEFAULT, GLib.Cancellable? cancellable = null) throws GLib.Error {
      unowned GLib.MainContext? thread_context = GLib.MainContext.get_thread_default ();
      GLib.IdleSource idle_source = new GLib.IdleSource ();
      idle_source.set_callback (execute_async.callback);

      this.add (() => {
          idle_source.attach (thread_context);

          return false;
        }, priority, cancellable);
      yield;

      return func ();
    }

    /**
     * Execute a callback in a background thread
     *
     * Although the supplied callback will be executed in a background
     * thread, the async function call will be finished in an idle
     * callback for the thread-default main context.
     *
     * @param func the callback to execute
     * @param priority the priority
     * @param cancellable optional cancellable for aborting the
     *   operation
     */
    public virtual async G execute_background<G> (owned Callback<G> func, int priority = GLib.Priority.DEFAULT, GLib.Cancellable? cancellable = null) throws GLib.Error {
      unowned GLib.MainContext? thread_context = GLib.MainContext.get_thread_default ();
      GLib.IdleSource idle_source = new GLib.IdleSource ();
      idle_source.set_callback (execute_background.callback);

      Bump.TaskQueue.ThreadCallbackData<G> data = new ThreadCallbackData<G> ();
      data.thread_func = () => {
        try {
          return func ();
        } finally {
          idle_source.attach (thread_context);
        }
      };
      this.add (data.source_func);
      yield;

      if ( data.error != null )
        throw data.error;

      return data.return_value;
    }

    private static unowned TaskQueue? global_queue = null;

    construct {
      this.queue = new Bump.CallbackQueue<Bump.TaskQueue.Data> ();
      this.queue.consumer_shortage.connect (() => { this.spawn (-1); });
    }

    /**
     * Get the global task queue
     *
     * This will retrieve a global task queue, creating it if it does
     * not exist.
     */
    public static TaskQueue get_global () {
      TaskQueue? gp = global_queue;

      if ( gp == null ) {
        lock ( global_queue ) {
          if ( global_queue == null ) {
            global_queue = gp = new TaskQueue ();
            gp.add_weak_pointer (&global_queue);
          } else {
            gp = global_queue;
          }
        }
      }

      return gp;
    }
  }
}
