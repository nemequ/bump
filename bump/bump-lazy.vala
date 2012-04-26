namespace Bump {
  /**
   * Lazy initializer
   */
  public class Lazy<T> : GLib.Object {
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
    private T? value = null;

    /**
     * Whether or not the value has already been initialized
     */
    public bool is_initialized {
      get {
        return this.value != null;
      }
    }

    /**
     * Prepare a resource synchronously
     *
     * @return the newly prepared resource
     */
    protected virtual T prepare () throws GLib.Error {
      if ( typeof (T).is_a (typeof (GLib.Object)) ) {
        T? result = (T) GLib.Object.new (typeof (T));

        if ( typeof (T).is_a (typeof (GLib.Initable)) )
          if ( !((GLib.Initable) result).init (null) )
            throw new GLib.IOError.FAILED ("Unable to initialize a new %s: unknown error.", typeof (T).name);

        return result;
      } else {
        throw new GLib.IOError.NOT_SUPPORTED ("Attempted to prepare a %s resource without implementing a method to do so.", typeof (T).name);
      }
    }

    /**
     * Prepare a resource asynchronously
     *
     * @return the newly prepared resource
     */
    protected virtual async T prepare_async () throws GLib.Error {
      T? result = null;

      if ( typeof (T).is_a (typeof (GLib.AsyncInitable)) ) {
        result = (T) GLib.Object.new (typeof (T));

        unowned GLib.AsyncInitable ai = (GLib.AsyncInitable) result;
        bool success = yield ai.init_async (GLib.Priority.DEFAULT, null);
        if ( !success )
          throw new GLib.IOError.FAILED ("Unable to initialize a new %s: unknown error.", typeof (T).name);

        return result;
      } else {
        return yield this.pool.execute_async<T> (() => { return this.prepare (); });
      }
    }

    /**
     * Prepare a resource in a background thread
     *
     * @return the newly prepared resource
     */
    protected virtual async T prepare_background () throws GLib.Error {
      return yield this.pool.execute_background<T> (() => { return this.prepare (); });
    }

    /**
     * Retrieve the value, initializing it if necessary
     *
     * @return the value
     */
    public unowned T get_value () throws GLib.Error {
      if ( this.value == null ) {
        this.sem.lock ();
        try {
          if ( this.value == null ) {
            this.value = this.prepare ();
          }
        } finally {
          this.sem.unlock ();
        }
      }

      return this.value;
    }

    /**
     * Retrieve the value, initializing it in an idle callback if
     * necessary
     *
     * @return the value
     */
    public async unowned T get_value_async () throws GLib.Error {
      if ( this.value == null ) {
        yield this.sem.lock_async ();
        try {
          if ( this.value == null ) {
            this.value = yield this.prepare_async ();
          }
        } finally {
          this.sem.unlock ();
        }
      }

      return this.value;
    }

    /**
     * Retrieve the value, initializing it in the background if
     * necessary
     *
     * @return the value
     */
    public async unowned T get_value_background () throws GLib.Error {
      if ( this.value == null ) {
        yield this.sem.lock_async ();
        try {
          if ( this.value == null ) {
            this.value = yield this.prepare_background ();
          }
        } finally {
          this.sem.unlock ();
        }
      }

      return this.value;
    }

    construct {
      if ( this.pool == null )
        this.pool = Bump.TaskQueue.get_global ();
    }
  }
}
