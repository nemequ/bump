namespace Bump {
  /**
   * Claim on a rivalrous resource
   *
   * This API allows for easy interoperability with exceptions without
   * forcing the use of callbacks, as the lock will be released
   * automatically when this class is destroyed.
   *
   * @see Semaphore.claim
   * @see ResourcePool.claim
   */
  public class Claim : GLib.Object, GLib.Initable, GLib.AsyncInitable {
    /**
     * Whether the claim is active
     */
    public bool active {
      get {
        return (time_acquired != 0) && (time_released == 0);
      }
    }

    /**
     * The time (monotonic) at which the lock was acquired
     */
    public int64 time_acquired { get; private set; }

    /**
     * The time (monotonic) at which the lock was released
     */
    public int64 time_released { get; private set; }

    /**
     * The length of time this claim has been held
     */
    public GLib.TimeSpan duration_held {
      get {
        if ( this.time_acquired == 0 ) {
          return 0;
        } else {
          return (GLib.TimeSpan) (((this.time_released == 0) ? GLib.get_monotonic_time () : this.time_released) - this.time_acquired);
        }
      }
    }

    /**
     * Release the lock
     */
    public virtual void release () {
      if ( this.time_acquired == 0 ) {
        GLib.critical ("Refusing to release a lock that was never held.");
      } else if ( this.time_released != 0 ) {
        GLib.critical ("Refusing to release a lock which has already been released.");
      } else {
        this.time_released = GLib.get_monotonic_time ();
      }
    }

    public virtual bool init (GLib.Cancellable? cancellable = null) throws GLib.Error {
      this.time_acquired = GLib.get_monotonic_time ();

      return true;
    }

    public virtual async bool init_async (int io_priority = GLib.Priority.DEFAULT, GLib.Cancellable? cancellable = null) throws GLib.Error {
      this.time_acquired = GLib.get_monotonic_time ();

      return true;
    }

    ~ Claim () {
      if ( this.time_released == 0 && this.time_acquired != 0 )
        this.release ();
    }
  }
}
