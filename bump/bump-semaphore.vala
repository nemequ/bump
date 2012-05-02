namespace Bump {
  /**
   * A high-level non-recursive counting semaphore
   *
   * This is a semaphore designed for asynchronous GObject programming. It
   * integrates well with the main event loop and provides features
   * such as prioritization, cancellation, and asynchronous
   * interfaces. Requests with higher priorities will always be
   * executed first, and requests of equal priorities will be executed
   * in the order in which they are requested.
   *
   * Unfortunately, this is relatively slow compared to lower level
   * mutex implementations such as GMutex and pthreads. If you don't
   * require the advanced features, or if you only need short-lived
   * locks, it would probably be much better to use GMutex.  However,
   * if you are writing an asynchronous GObject-based application the
   * convenience provided by these methods can go a long way towards
   * helping you write applications don't block the main loop and,
   * therefore, feel faster.
   */
  public class Semaphore : Bump.TaskQueue {
    /**
     * The maximum number of claims allowed
     */
    public int max_claims { get; construct; default = 1; }

    /**
     * The current number of claims
     */
    public int claims { get; private set; default = 0; }

    /**
     * Mutex to restrict access to internal structures
     *
     * This must never be locked while waiting on user defined code.
     */
    private GLib.Mutex mutex = GLib.Mutex ();

    /**
     * Cond which is activated when the lock is released
     */
    private GLib.Cond cond = GLib.Cond ();

    /**
     * Outstanding tasks
     */
    private unowned Bump.CallbackQueue<TaskQueue.Data> queue;

    /**
     * Pool used to process requests
     */
    public Bump.TaskQueue pool { get; construct; }

    /**
     * Release an anonymous claim
     *
     * @see lock
     * @see lock_async
     */
    public void unlock () {
      this.mutex.lock ();
      try {
        if ( this.claims > 0 ) {
          this.claims--;
          this.cond.signal ();
        } else {
          GLib.critical ("Unlocked a %s with 0 claims", this.get_type ().name ());
        }
      } finally {
        this.mutex.unlock ();
        this.spawn (-1);
      }
    }

    /**
     * Number of threads which are currently executing internal code
     *
     * This is used to help determine how many (if any) threads we
     * should spawn.
     */
    private int internal_threads = 0;

    public override bool process (GLib.TimeSpan wait = 0) {
      int64 wait_until = (wait >= 0) ? (GLib.get_monotonic_time () + wait) : int64.MAX;

      this.mutex.lock ();
      while ( this.claims >= this.max_claims || this.queue.length == 0 ) {
        if ( !this.cond.wait_until (this.mutex, wait_until) ) {
          this.mutex.unlock ();
          return false;
        }
      }

      TaskQueue.Data? data = this.queue.poll_timed (wait_until - GLib.get_monotonic_time ());
      if ( data != null ) {
        this.claims++;
      }

      this.mutex.unlock ();

      if ( data != null ) {
        lock ( this.internal_threads ) {
          this.internal_threads--;
        }
        data.process ();
        this.spawn (-1);
        lock ( this.internal_threads ) {
          this.internal_threads++;
        }
        return true;
      } else {
        return false;
      }
    }

    protected override int spawn (int max = -1) {
      if ( max < 0 ) {
        max = this.queue.length;
      } else {
        max = int.min (max, this.queue.length);
      }

      max = int.min (max, this.max_claims - this.claims);

      return (max != 0) ? base.spawn (max) : 0;
    }

    private void add_without_unlock (owned GLib.SourceFunc task, int priority = GLib.Priority.DEFAULT, GLib.Cancellable? cancellable = null) throws GLib.Error {
      Bump.TaskQueue.Data data = new Bump.TaskQueue.Data ();
      data.priority = priority;
      data.cancellable = cancellable;
      data.task = (owned) task;

      this.mutex.lock ();
      this.queue.offer (data);
      this.cond.signal ();
      this.mutex.unlock ();

      this.spawn (-1);
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
     * Synchronously acquire an anonymous claim
     *
     * You must release the claim with {@link unlock}.
     *
     * @param priority the priority with which to prepare the resource
     * @param cancellable optional cancellable for aborting the opearation
     * @see lock_async
     */
    public void @lock (int priority = GLib.Priority.DEFAULT, GLib.Cancellable? cancellable = null) throws GLib.Error {
      // TODO: easy to optimize this a bit for when there is no
      // resource contention.
      GLib.Mutex mut = GLib.Mutex ();
      mut.lock ();

      this.add_without_unlock (() => {
          mut.unlock ();

          return false;
        }, priority, cancellable);
      mut.lock ();
    }

    /**
     * Asynchronously acquire an anonymous claim
     *
     * You must release the claim with {@link unlock}.
     *
     * @param priority the priority with which to prepare the resource
     * @param cancellable optional cancellable for aborting the opearation
     * @see lock
     */
    public async void lock_async (int priority = GLib.Priority.DEFAULT, GLib.Cancellable? cancellable = null) throws GLib.Error {
      unowned GLib.MainContext? thread_context = GLib.MainContext.get_thread_default ();
      GLib.IdleSource idle_source = new GLib.IdleSource ();
      idle_source.set_callback (lock_async.callback);

      this.add_without_unlock (() => {
          idle_source.attach (thread_context);

          return false;
        }, priority, cancellable);
      yield;
    }

    /**
     * Synchronously acquire a claim
     *
     * @param priority the priority with which to prepare the resource
     * @param cancellable optional cancellable for aborting the opearation
     * @see claim_async
     */
    public virtual Bump.SemaphoreClaim claim (int priority = GLib.Priority.DEFAULT, GLib.Cancellable? cancellable = null) throws GLib.Error {
      Bump.SemaphoreClaim claim = new Bump.SemaphoreClaim (this);
      claim.init (cancellable);
      return claim;
    }

    /**
     * Asynchronously acquire a claim
     *
     * @param priority the priority with which to prepare the resource
     * @param cancellable optional cancellable for aborting the opearation
     * @see claim
     */
    public virtual async Bump.SemaphoreClaim claim_async (int priority = GLib.Priority.DEFAULT, GLib.Cancellable? cancellable = null) throws GLib.Error {
      Bump.SemaphoreClaim claim = new Bump.SemaphoreClaim (this);
      yield claim.init_async (priority, cancellable);
      return claim;
    }

    construct {
      this.queue = this.get_queue ();
      if ( this.pool == null ) {
        this.pool = Bump.TaskQueue.get_global ();
      }
    }

    public Semaphore (int max_claims = 1) {
      GLib.Object (max_claims: max_claims);
    }
  }
}
