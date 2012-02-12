namespace Bump {
  /**
   * Claim on a resource from a {@link Bump.ResourcePool}
   */
  public class ResourceClaim<T> : Bump.Claim {
    public Bump.ResourcePool<T> pool { get; construct; }

    private unowned T? _resource = null;
    public unowned T? resource {
      get {
        if ( this._resource == null ) {
          if ( this.time_released == 0 ) {
            lock ( this._resource ) {
              if ( this._resource == null ) {
                if ( this.time_released == 0 ) {
                  try {
                    this.init ();
                  } catch ( GLib.Error e ) {
                    GLib.critical ("Unable to initialize resource claim: %s", e.message);
                  }
                } else {
                  GLib.critical ("Attempted to read a resource which has already been released.");
                }

                return this._resource;
              }
            }
          }
        }

        return this._resource;
      }
    }

    public override void release () {
      base.release ();
      if ( this._resource != null ) {
        lock ( this._resource ) {
          this.pool.release (this._resource);
          this._resource = null;
        }
      }
    }

    public override bool init (GLib.Cancellable? cancellable = null) throws GLib.Error {
      this._resource = this.pool.acquire (GLib.Priority.DEFAULT, cancellable);
      return base.init (cancellable);
    }

    public override async bool init_async (int io_priority = GLib.Priority.DEFAULT, GLib.Cancellable? cancellable = null) throws GLib.Error {
      this._resource = yield this.pool.acquire_async (GLib.Priority.DEFAULT, cancellable);
      return yield base.init_async (io_priority, cancellable);
    }

    ~ SemaphoreClaim () {
      if ( this.time_released == 0 && this.time_acquired != 0 )
        this.release ();
    }

    public ResourceClaim (Bump.ResourcePool pool) {
      GLib.Object (pool: pool);
    }
  }
}
