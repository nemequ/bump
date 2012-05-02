namespace Bump {
  /**
   * Object which creates other objects
   *
   * In order to acquire an instance of the type the factory creates
   * you should use one of the acquire methods ({@link acquire},
   * {@link acquire_async}, and {@link acquire_background}). The
   * create methods exist to be overridden in order to properly
   * integrate with subclasses and should not be called directly
   * except from within acquire implementations.
   */
  public abstract class Factory<G> : GLib.Object {
    /**
     * Properties used for GObject construction
     *
     * These properties are used by the default implementations of
     * {@link create}, {@link create_async}, and {@link create_background}.
     */
    public GLib.Parameter[]? construct_properties { get; set; default = null; }

    /**
     * Create an instance synchronously
     *
     * The default implementation will handle creation of classes
     * derived from {@link GLib.Object} as well as initialization of
     * {@link GLib.Initable} implementations. You can override this
     * method in a subclass to provide a customized method for
     * instantiating your object synchronously.
     *
     * @return the newly created instance
     */
    protected virtual G create (int priority = GLib.Priority.DEFAULT, GLib.Cancellable? cancellable = null) throws GLib.Error {
      if ( typeof (G).is_a (typeof (GLib.Object)) ) {
        G? result = (G) GLib.Object.newv (typeof (G), this.construct_properties);

        if ( typeof (G).is_a (typeof (GLib.Initable)) )
          if ( !((GLib.Initable) result).init (cancellable) )
            throw new GLib.IOError.FAILED ("Unable to initialize a new %s: unknown error.", typeof (G).name);

        return result;
      } else {
        throw new GLib.IOError.NOT_SUPPORTED ("Attempted to create a %s instance without implementing a method to do so.", typeof (G).name);
      }
    }

    /**
     * Create an instance asynchronously
     *
     * For classes which implement {@link GLib.AsyncInitable}, the
     * default implementation will create an instance of the class
     * using {@link GLib.Object.new} then initialize the instance
     * using {@link GLib.AsyncInitable.init_async}. Otherwise, the
     * default implementation will simply invoke {@link create} in an
     * idle callback. You can override this method in a subclass to
     * provide a customized method for instantiating your object
     * asynchronously.
     *
     * @return the newly created instance
     */
    protected virtual async G create_async (int priority = GLib.Priority.DEFAULT, GLib.Cancellable? cancellable = null) throws GLib.Error {
      G? result = null;

      if ( typeof (G).is_a (typeof (GLib.AsyncInitable)) ) {
        result = (G) GLib.Object.newv (typeof (G), this.construct_properties);

        unowned GLib.AsyncInitable ai = (GLib.AsyncInitable) result;
        bool success = yield ai.init_async (priority, cancellable);
        if ( !success )
          throw new GLib.IOError.FAILED ("Unable to initialize a new %s: unknown error.", typeof (G).name);

        return result;
      } else {
        return yield Bump.TaskQueue.get_global ().execute_async<G> (() => { return this.create (); }, priority, cancellable);
      }
    }

    /**
     * Create an instance in a background thread
     *
     * The default implementation will call {@link create} in a
     * background thread. You can override this method in a subclass
     * to provide a customized method for instantiating your object in
     * a background thread.
     *
     * @return the newly created instance
     */
    protected virtual async G create_background (int priority = GLib.Priority.DEFAULT, GLib.Cancellable? cancellable = null) throws GLib.Error {
      return yield Bump.TaskQueue.get_global ().execute_background<G> (() => { return this.create (); }, priority, cancellable);
    }

    /**
     * Synchronously acquire an instance
     *
     * @param priority the priority with which to create the instance
     * @param cancellable optional cancellable for aborting the opearation
     * @return the instance
     * @see acquire_async
     * @see acquire_background
     */
    public abstract unowned G acquire (int priority = GLib.Priority.DEFAULT, GLib.Cancellable? cancellable = null) throws GLib.Error;

    /**
     * Asynchronously acquire an instance
     *
     * @param priority the priority with which to create the instance
     * @param cancellable optional cancellable for aborting the opearation
     * @return the instance
     * @see acquire
     * @see acquire_background
     */
    public abstract async unowned G acquire_async (int priority = GLib.Priority.DEFAULT, GLib.Cancellable? cancellable = null) throws GLib.Error;

    /**
     * Asynchronously acquire an instance in a background thread
     *
     * @param priority the priority with which to create the instance
     * @param cancellable optional cancellable for aborting the opearation
     * @return the instance
     * @see acquire
     * @see acquire_async
     */
    public abstract async unowned G acquire_background (int priority = GLib.Priority.DEFAULT, GLib.Cancellable? cancellable = null) throws GLib.Error;
  }
}
