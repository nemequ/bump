namespace Bump {
  /**
   * Lazy initializer
   */
  public class Lazy<T> : Bump.Factory<T> {
    /**
     * Pool used to process requests
     */
    public Bump.TaskQueue pool { get; construct; }

    /**
     * Semaphore used to block during initialization
     */
    private Bump.Semaphore sem = new Bump.Semaphore (1);

    /**
     * The actual value
     */
    private T? _value = null;

    /**
     * The value
     *
     * This is roughly equivalent to calling {@link acquire}
     */
    public T value {
      get {
        unowned T? value = null;
        try {
          value = this.acquire ();
        } catch ( GLib.Error e ) {
          GLib.critical (e.message);
        }
        return value;
      }
    }

    /**
     * Whether or not the value has already been initialized
     */
    public bool is_initialized {
      get {
        return this._value != null;
      }
    }

    private static int lock_cnt = 0;

    /**
     * {@inheritDoc}
     */
    public override unowned T acquire (int priority = GLib.Priority.DEFAULT, GLib.Cancellable? cancellable = null) throws GLib.Error {
      if ( this._value == null ) {
        GLib.AtomicInt.add (ref lock_cnt, 1);
        this.sem.lock ();

        try {
          if ( this._value == null ) {
            this._value = this.create (priority, cancellable);
          }
        } finally {
          this.sem.unlock ();
        }
      }

      return this._value;
    }

    /**
     * {@inheritDoc}
     */
    public override async unowned T acquire_async (int priority = GLib.Priority.DEFAULT, GLib.Cancellable? cancellable = null) throws GLib.Error {
      if ( this._value == null ) {
        yield this.sem.lock_async ();
        try {
          if ( this._value == null ) {
            this._value = yield this.create_async (priority, cancellable);
          }
        } finally {
          this.sem.unlock ();
        }
      }

      return this._value;
    }

    /**
     * {@inheritDoc}
     */
    public override async unowned T acquire_background (int priority = GLib.Priority.DEFAULT, GLib.Cancellable? cancellable = null) throws GLib.Error {
      if ( this._value == null ) {
        yield this.sem.lock_async ();
        try {
          if ( this._value == null ) {
            this._value = yield this.create_background (priority, cancellable);
          }
        } finally {
          this.sem.unlock ();
        }
      }

      return this._value;
    }

    construct {
      if ( this.pool == null )
        this.pool = Bump.TaskQueue.get_global ();
    }
  }
}
