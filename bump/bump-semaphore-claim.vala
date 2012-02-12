namespace Bump {
  /**
   * Claim on a semaphore
   */
  public class SemaphoreClaim : Bump.Claim {    
    /**
     * The {@link Bump.Semaphore} which this claim operates on
     */
    public Semaphore semaphore { get; construct; }

    public override void release () {
      base.release ();
      this.semaphore.unlock ();
    }

    public override bool init (GLib.Cancellable? cancellable = null) throws GLib.Error {
      this.semaphore.lock (GLib.Priority.DEFAULT, cancellable);
      return base.init (cancellable);
    }

    public override async bool init_async (int io_priority = GLib.Priority.DEFAULT, GLib.Cancellable? cancellable = null) throws GLib.Error {
      yield this.semaphore.lock_async ();
      return yield base.init_async (io_priority, cancellable);
    }

    /**
     * Create a new claim
     *
     * @param priority the priority
     * @param cancellable optional cancellable
     */
    internal SemaphoreClaim (Semaphore semaphore) {
      GLib.Object (semaphore: semaphore);
    }

    ~ SemaphoreClaim () {
      if ( this.time_released == 0 && this.time_acquired != 0 )
        this.release ();
    }
  }
}
