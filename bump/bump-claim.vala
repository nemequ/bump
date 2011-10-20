namespace Bump {
  /**
   * Represents a claim to a mutex
   *
   * This API allows for easy interoperability with exceptions without
   * forcing the use of callbacks, as the lock will be released
   * automatically when this class is destroyed.
   */
  public class Claim : GLib.Object {    
    /**
     * The @{link Bump.Mutex} which this claim operates on
     */
    public Mutex mutex { get; construct; }

    /**
     * Whether the claim is active (i.e., locking the @{link mutex})
     */
    public bool active {
      get {
        return (time_acquired != null) && (time_released == null);
      }
    }

    /**
     * The time at which the lock was acquired
     */
    private GLib.DateTime? time_acquired = null;

    /**
     * The time at which the lock was released
     */
    private GLib.DateTime? time_released = null;

    /**
     * The length of time this claim has been held
     */
    public GLib.TimeSpan duration_held {
      get {
        if ( this.time_acquired == null ) {
          return 0;
        } else {
          return (this.time_released ?? new GLib.DateTime.now_utc ()).difference (this.time_acquired);
        }
      }
    }

    /**
     * Release the lock
     */
    public virtual signal void release () {
      if ( this.time_acquired == null ) {
        GLib.critical ("Refusing to release a lock that was never held.");
      } else if ( this.time_released != null ) {
        GLib.critical ("Refusing to release a lock which has already been released.");
      } else {
        /* We want to record the time before we actually unlock the
         * mutex because, for some Mutex implementations, it is
         * possible that unlocking will begin another task, and we
         * don't want that included in our total. This means holding
         * the lock a little bit longer, but at least it is safe. */
        this.time_released = new GLib.DateTime.now_utc ();
        this.mutex.unlock ();
      }
    }

    public virtual bool init (GLib.Cancellable? cancellable = null) throws GLib.Error {
      this.mutex.lock ();
      this.time_acquired = new GLib.DateTime.now_utc ();

      return true;
    }

    public virtual async bool init_async (int io_priority = GLib.Priority.DEFAULT, GLib.Cancellable? cancellable = null) throws GLib.Error {
      yield this.mutex.lock_async ();
      this.time_acquired = new GLib.DateTime.now_utc ();

      return true;
    }

    ~ Claim () {
      if ( this.active ) {
        this.release ();
      }
    }

    /**
     * Create a new claim
     *
     * @param priority the priority
     * @param cancellable optional cancellable
     */
    internal Claim (Mutex mutex) {
      GLib.Object (mutex: mutex);
    }
  }
}
