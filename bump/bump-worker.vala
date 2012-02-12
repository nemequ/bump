namespace Bump {
  /**
   * A worker for executing a task in the background
   */
  public abstract class Worker : GLib.Object {
    private int _progress = -1;
    /**
     * How many units of progress have been completed
     *
     * If work has not yet begun the value of this property should be
     * -1. While the worker is active, it should be a non-negative
     * integer less than {@link total}. Once work has completed, it
     * should be equal to {@link total}.
     *
     * Setting the value to 0 is what triggers {@link started} to be
     * set, so you must not omit this step if you want accurate timing
     * information.
     */
    public int progress {
      get {
        return this._progress;
      }

      set {
        this._progress = value;

        GLib.DateTime now = new GLib.DateTime.now_utc ();

        if ( value == 0 ) {
          this.started = now;
          this.elapsed = 0;
        } else {
          this.elapsed = now.difference (this.started);
        }

        if ( value == this.total ) {
          this.finished ();
        }
      }
    }

    /**
     * Total units of progress until the worker finishes
     */
    public int total { get; set; }

    /**
     * Priority of the worker
     */
    public int priority { get; construct; default = GLib.Priority.DEFAULT; }

    /**
     * Optional cancellable for aborting the worker
     */
    public GLib.Cancellable? cancellable { get; construct; }

    /**
     * Number of elapsed microseconds as of the last progress event
     */
    private GLib.TimeSpan elapsed = 0;

    /**
     * Time at which the worker started working
     *
     * When overriding run/run_async, you should set this property.
     *
     * @see start
     */
    public GLib.DateTime? started { get; protected set; default = null; }

    /**
     * Convenience method to set the started property
     *
     * @see started
     */
    protected void start () {
      if ( this.started == null )
        this.started = new GLib.DateTime.now_utc ();
    }

    /**
     * The expected time it will take to complete.
     *
     * The current default implementation is currently quite naïve.
     * It will assume that time required for each unit of future
     * progress will be equal to the average time of past progress. In
     * the future, this will likely be adjusted to give more weight to
     * recent progress.
     */
    public virtual GLib.TimeSpan guess_remaining_time () {
      if ( this.progress <= 0 || this.started == null )
        return -1;

      // TODO: Make this thread-safe
      GLib.TimeSpan elapsed = this.elapsed;
      int progress = this.progress;
      int total = this.total;
      GLib.DateTime now = new GLib.DateTime.now_utc ();

      GLib.TimeSpan average = elapsed / progress;
      GLib.TimeSpan average2 = now.difference (this.started) / (progress + 1);
      GLib.DateTime eta = this.started.add (((average < average2) ? average : average2) * total);

      GLib.TimeSpan rt = eta.difference (now);
      return (rt >= 0) ? rt : 0;
    }

    /**
     * Emitted when the worker finishes
     */
    public virtual signal void finished () {
      if ( this.progress != this.total )
        this.progress = this.total;
    }

    /**
     * Run the worker, blocking until a result is obtained
     */
    public abstract void run ();

    /**
     * Run the worker in the background
     */
    public abstract async void run_async ();
  }
}
