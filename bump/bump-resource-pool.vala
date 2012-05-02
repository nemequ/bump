namespace Bump {
  /**
   * Pool of reusable resources
   *
   * This class is designed to help manage a group of reusable
   * resources, especially those that are expensive to acquire. The
   * pool will automatically grow, and shrink, as required.
   */
  public class ResourcePool<T> : Bump.Factory<T> {
    /**
     * Delegate type for {@link ResourcePool}
     *
     * @param resource the resource
     * @return value to return to the invoker
     * @see execute
     * @see execute_async
     * @see execute_background
     */
    public delegate R Callback<T,R> (T resource) throws GLib.Error;

    /**
     * Maximum number of resources allowed at any given time
     *
     * If you do not wish to limit the size of the pool use
     * 0. Resources will be created as needed and destroyed according
     * to {@link max_idle_time}.
     */
    public int max_resources { get; construct; default = 0; }

    /**
     * Amount of time a resource should stay idle before being closed
     *
     * Note that this is currently only accurate to around 1 second,
     * and then only if you're not blocking the main loop.
     */
    public GLib.TimeSpan max_idle_time { get; set; default = GLib.TimeSpan.SECOND; }

    /**
     * Event ID of the cleanup callback
     */
    private uint cleanup_source = 0;

    /**
     * Container class for the resources and the related metadata
     */
    private class Resource<T> {
      /**
       * The resource
       */
      public T resource;

      /**
       * Time the resource was last used
       */
      public int64 last_used;

      public void use () {
        this.last_used = GLib.get_monotonic_time ();
      }

      public Resource (owned T resource) {
        this.resource = (owned) resource;
        this.use ();
      }
    }

    /**
     * List of currently idle resources
     */
    private GLib.Queue<Bump.ResourcePool.Resource<T>> idle_resource_queue =
      new GLib.Queue<Bump.ResourcePool.Resource<T>> ();

    /**
     * List of currently active resources
     */
    private GLib.HashTable<unowned T, Bump.ResourcePool.Resource<T>> active_resources_ht =
      new GLib.HashTable<unowned T, Bump.ResourcePool.Resource<T>> (GLib.direct_hash, GLib.direct_equal);

    /**
     * Number of resources which currently exist
     */
    public int num_resources { get; private set; }

    /**
     * Number of currently idle resources
     */
    public int idle_resources {
      get {
        lock ( this.idle_resource_queue ) {
          return (int) this.idle_resource_queue.length;
        }
      }
    }

    /**
     * Number of currently active resources
     */
    public int active_resources {
      get {
        lock ( this.active_resources_ht ) {
          return (int) this.active_resources_ht.size ();
        }
      }
    }

    /**
     * Pool used to process requests
     */
    public Bump.TaskQueue pool { get; construct; }

    private Bump.TaskQueue? resource_lock = null;

    private bool cleanup () {
      unowned ResourcePool.Resource<T>? res = null;
      int64 now = GLib.get_monotonic_time ();
      int64 threshold = now - this.max_idle_time;
      GLib.SList<ResourcePool.Resource<T>> free_list = new GLib.SList<ResourcePool.Resource<T>> ();
      int free_list_len = 0;

      lock ( this.idle_resource_queue ) {
        while ( (res = this.idle_resource_queue.peek_tail ()) != null && res.last_used < threshold ) {
          free_list_len++;
          free_list.prepend (this.idle_resource_queue.pop_tail ());
        }
      }

      if ( free_list_len > 0 ) {
        lock ( this.num_resources ) {
          this.num_resources -= free_list_len;
        }
      }

      if ( res != null ) {
        int64 next_cleanup_in = (res.last_used + this.max_idle_time) - now;
        this.cleanup_source = GLib.Timeout.add_seconds ((uint) int64.max (next_cleanup_in / GLib.TimeSpan.SECOND, 1),
                                                        this.cleanup, GLib.Priority.LOW);
      }

      this.cleanup_source = 0;
      return false;
    }

    /**
     * Register a newly acquire resource as active
     *
     * @param resource the resource to register
     * @return an unowned reference to the resource (for chaining)
     */
    private unowned T register (owned T resource) throws GLib.Error {
      lock ( this.num_resources ) {
        this.num_resources++;
      }

      ResourcePool.Resource<T> res = new ResourcePool.Resource<T> ((owned) resource);

      lock ( this.active_resources_ht ) {
        this.active_resources_ht[res.resource] = res;
      }

      return res.resource;
    }

    /**
     * Release a resource into the pool
     *
     * @param resource the resource to release
     */
    public virtual void release (T resource) {
      ResourcePool.Resource<T>? res = null;

      lock ( this.active_resources_ht ) {
        res = this.active_resources_ht[resource];
        if ( res == null ) {
          GLib.warning ("Attempted to release an unknown resource.");
          return;
        }
        this.active_resources_ht.remove (resource);
      }

      res.use ();

      lock ( this.idle_resource_queue ) {
        this.idle_resource_queue.push_head (res);

        if ( this.cleanup_source == 0 )
          this.cleanup_source = GLib.Timeout.add_seconds ((uint) int64.max (1, this.max_idle_time / GLib.TimeSpan.SECOND), this.cleanup);
      }

      if ( this.resource_lock is Bump.Semaphore ) {
        ((Bump.Semaphore) this.resource_lock).unlock ();
      }
    }

    /**
     * Attempt to acquire a resource without blocking
     *
     * @return the resource, or null if none was available
     */
    private unowned T? try_acquire_unlocked () {
      Bump.ResourcePool.Resource<T>? res = null;

      lock ( this.idle_resource_queue ) {
        res = this.idle_resource_queue.pop_head ();
      }

      if ( res == null )
        return null;

      lock ( this.active_resources_ht ) {
        this.active_resources_ht[res.resource] = res;
      }

      return res.resource;
    }

    /**
     * Synchronously acquire a resource
     *
     * @param priority the priority with which to create the resource
     * @param cancellable optional cancellable for aborting the opearation
     * @return the resource
     * @see acquire_async
     * @see acquire_background
     */
    public override unowned T acquire (int priority = GLib.Priority.DEFAULT, GLib.Cancellable? cancellable = null) throws GLib.Error {
      if ( this.resource_lock is Bump.Semaphore )
        ((Bump.Semaphore) this.resource_lock).lock (priority, cancellable);

      try {
        unowned T? resource = this.try_acquire_unlocked ();
        if ( resource != null )
          return resource;
        else
          return this.register (this.create (priority, cancellable));
      } catch ( GLib.Error e ) {
        if ( this.resource_lock is Bump.Semaphore )
          ((Bump.Semaphore) this.resource_lock).unlock ();
        throw e;
      }
    }

    /**
     * Asynchronously acquire a resource
     *
     * @param priority the priority with which to create the resource
     * @param cancellable optional cancellable for aborting the opearation
     * @return the resource
     * @see acquire
     * @see acquire_background
     */
    public override async unowned T acquire_async (int priority = GLib.Priority.DEFAULT, GLib.Cancellable? cancellable = null) throws GLib.Error {
      if ( this.resource_lock is Bump.Semaphore )
        yield ((Bump.Semaphore) this.resource_lock).lock_async (priority, cancellable);

      try {
        unowned T? resource = this.try_acquire_unlocked ();
        if ( resource != null )
          return resource;
        else {
          return this.register (yield this.create_async (priority, cancellable));
        }
      } catch ( GLib.Error e ) {
        if ( this.resource_lock is Bump.Semaphore )
          ((Bump.Semaphore) this.resource_lock).unlock ();
        throw e;
      }
    }

    /**
     * Asynchronously acquire a resource in a background thread
     *
     * @param priority the priority with which to create the resource
     * @param cancellable optional cancellable for aborting the opearation
     * @return the resource
     * @see acquire
     * @see acquire_async
     */
    public override async unowned T acquire_background (int priority = GLib.Priority.DEFAULT, GLib.Cancellable? cancellable = null) throws GLib.Error {
      if ( this.resource_lock is Bump.Semaphore )
        yield ((Bump.Semaphore) this.resource_lock).lock_async (priority, cancellable);

      try {
        unowned T? resource = this.try_acquire_unlocked ();
        if ( resource != null ) {
          return resource;
        } else {
          return this.register (yield this.create_background (priority, cancellable));
        }
      } catch ( GLib.Error e ) {
        if ( this.resource_lock is Bump.Semaphore )
          ((Bump.Semaphore) this.resource_lock).unlock ();
        throw e;
      }
    }

    /**
     * Execute a callback which uses a resource
     *
     * @param func the callback to execute
     * @param priority the priority with which to create the resource
     * @param cancellable optional cancellable for aborting the opearation
     * @return the return value from the callback
     * @see execute_async
     * @see execute_background
     */
    public R execute<R> (ResourcePool.Callback<T,R> func, int priority = GLib.Priority.DEFAULT, GLib.Cancellable? cancellable = null) throws GLib.Error {
      unowned T res = this.acquire (priority, cancellable);
      try {
        return func (res);
      } finally {
        this.release (res);
      }
    }

    /**
     * Asynchronously execute a callback which uses a resource
     *
     * @param func the callback to execute
     * @param priority the priority with which to create the resource
     * @param cancellable optional cancellable for aborting the opearation
     * @return the return value from the callback
     * @see execute
     * @see execute_background
     */
    public async R execute_async<R> (owned ResourcePool.Callback<T,R> func, int priority = GLib.Priority.DEFAULT, GLib.Cancellable? cancellable = null) throws GLib.Error {
      unowned T res = yield this.acquire_async (priority, cancellable);
      try {
        return yield this.pool.execute_async<R> (() => {
            return func (res);
          }, priority, cancellable);
      } finally {
        this.release (res);
      }
    }

    /**
     * Execute a callback in a background thread which uses a resource
     *
     * @param func the callback to execute
     * @param priority the priority with which to create the resource
     * @param cancellable optional cancellable for aborting the opearation
     * @return the return value from the callback
     * @see execute
     * @see execute_async
     */
    public async R execute_background<R> (owned ResourcePool.Callback<T,R> func, int priority = GLib.Priority.DEFAULT, GLib.Cancellable? cancellable = null) throws GLib.Error {
      unowned T res = yield this.acquire_background (priority, cancellable);
      try {
        return yield this.pool.execute_background<R> (() => {
            return func (res);
          }, priority, cancellable);
      } finally {
        this.release (res);
      }
    }

    /**
     * Acquire a claim
     *
     * @param priority the priority with which to create the resource
     * @param cancellable optional cancellable for aborting the opearation
     * @return the newly acquired (and initialized) claim
     * @see claim_async
     */
    public Bump.ResourceClaim<T> claim (int priority = GLib.Priority.DEFAULT, GLib.Cancellable? cancellable = null) throws GLib.Error {
      Bump.ResourceClaim<T> rc = new Bump.ResourceClaim<T> (this);
      rc.init (cancellable);
      return rc;
    }

    /**
     * Acquire a claim asynchronously
     *
     * @param priority the priority with which to create the resource
     * @param cancellable optional cancellable for aborting the opearation
     * @return the newly acquired (and initialized) claim
     * @see claim
     */
    public async Bump.ResourceClaim<T> claim_async (int priority = GLib.Priority.DEFAULT, GLib.Cancellable? cancellable = null) throws GLib.Error {
      Bump.ResourceClaim<T> rc = new Bump.ResourceClaim<T> (this);
      yield rc.init_async (priority, cancellable);
      return rc;
    }

    /**
     * Create a resource pool
     *
     * @param max_resources the maximum number of resources allowed at
     *   any given time (0 for unlimited)
     */
    public ResourcePool (int max_resources = -1) {
      GLib.Object (max_resources: max_resources);
    }

    construct {
      if ( this.pool == null )
        this.pool = Bump.TaskQueue.get_global ();

      this.resource_lock = (this.max_resources > 0) ? new Bump.Semaphore (this.max_resources) : this.pool;
    }
  }
}
