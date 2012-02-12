namespace Bump {
  /**
   * A structure which spawns threads
   */
  public interface Threading : GLib.Object, Bump.Queue {
    private const string PRIVATE_DATA_NAME = "__BumpThreading_private_data__";

    private struct Data {
      public GLib.Mutex mutex;
      public int max_threads;
      public GLib.TimeSpan max_idle_time;
      public int num_threads;
      public int idle_threads;

      public GLib.HashTable<GLib.Thread<void*>,unowned GLib.Thread<void*>>? threads;

      public static void* alloc () {
        Threading.Data* data = GLib.Slice.alloc0 (sizeof (Threading.Data));
        data->mutex.init ();
        data->max_threads = -1;
        data->max_idle_time = GLib.TimeSpan.SECOND;
        data->threads = new GLib.HashTable<GLib.Thread,GLib.Thread> (GLib.direct_hash, GLib.direct_equal);
        return data;
      }

      public static void dealloc (void* ptr) {
        Threading.Data* data = (Threading.Data*) ptr;
        data->threads = null;
        GLib.Slice.free (sizeof (Threading.Data), ptr);
      }
    }

    /**
     * Retrieve private data used by the {@link Threading} mix-in
     *
     * The private data must have been previously allocated using
     * {@link private_data_new}
     *
     * @return pointer to the private data
     */
    private Threading.Data* get_private_data () {
      Threading.Data* data = this.get_data<Threading.Data*> (PRIVATE_DATA_NAME);
      if ( data == null ) {
        data = Threading.Data.alloc ();
        this.set_data_full (PRIVATE_DATA_NAME, data, Threading.Data.dealloc);
      }
      return data;
    }

    /**
     * Get the maximum number of threads to spawn
     *
     * Note that this isn't necessarily the maximum number of threads
     * which could be in use, since threads spawned prior to lowering
     * this value will not be destroyed until {@link max_idle_time} is
     * exceeded.
     *
     * @return the maximum number of threads, or -1 for unlimited
     * @see set_max_threads
     * @see increase_max_threads
     */
    public int get_max_threads () {
      return ((Threading.Data*) this.get_private_data ()).max_threads;
    }

    /**
     * Set the maximum number of threads to spawn
     *
     * Note that this isn't necessarily the maximum number of threads
     * which could be in use, since threads spawned prior to lowering
     * this value will not be destroyed until {@link max_idle_time} is
     * exceeded.
     *
     * If you want to increase the maximum number of threads, you
     * should use {@link increase_max_threads} instead.
     *
     * @param value the maximum number of threads, or -1 for unlimited
     * @see get_max_threads
     * @see increase_max_threads
     */
    public void set_max_threads (int value) {
      Threading.Data* data = (Threading.Data*) this.get_private_data ();
      data->mutex.lock ();
      data->max_threads = value;
      data->mutex.unlock ();
    }

    /**
     * Get the maximum amount of time to allow a thread to remain unused
     *
     * For unlimited, use -1. For none, use 0.
     *
     * @return The maximum amount of time (in microseconds) to allow a
     *   thread to remain unused before removing it
     * @see set_max_idle_time
     */
    public GLib.TimeSpan get_max_idle_time () {
      return ((Threading.Data*) this.get_private_data ()).max_idle_time;
    }

    /**
     * Set the maximum amount of time to allow a thread to remain unused
     *
     * For unlimited, use -1. For none, use 0.
     *
     * Changing this value will not have any effect on an already
     * waiting thread, though the thread will pick up the new value
     * next time it needs to wait.
     *
     * @value maximum amount of time (in microseconds) to allow a
     *   thread to remain unused before removing it
     * @see set_max_idle_time
     */
    public void set_max_idle_time (GLib.TimeSpan value) {
      Threading.Data* data = (Threading.Data*) this.get_private_data ();
      data->mutex.lock ();
      data->max_idle_time = value;
      data->mutex.unlock ();
    }

    /**
     * Total number of threads currently running
     *
     * @return number of threads currently running
     * @see idle_threads
     */
    public int get_num_threads () {
      return ((Threading.Data*) this.get_private_data ()).num_threads;
    }

    /**
     * Number of threads currently waiting for input
     *
     * @return number of threads waiting for input
     */
    public int get_idle_threads () {
      return ((Threading.Data*) this.get_private_data ()).idle_threads;
    }

    /**
     * Update the max_threads property to the new value if it permits
     * more threads than the old value.
     *
     * Setting the max_threads using {@link set_max_threads} can
     * clobber the value, so you should prefer to use this method if
     * you want to increase the number of threads.
     *
     * @param new_max_threads new maximum number of threads
     * @see set_max_threads
     * @see get_max_threads
     */
    public void increase_max_threads (int new_max_threads) {
      Threading.Data* data = (Threading.Data*) this.get_private_data ();
      if ( data->max_threads > 0 && data->max_threads < new_max_threads ) {
        data->mutex.lock ();
        if ( data->max_threads > 0 && data->max_threads < new_max_threads ) {
          data->max_threads = new_max_threads;
        }
        data->mutex.unlock ();
      }
    }

    /**
     * Run user-provided code
     *
     * Implementations should use this method to execute user provided
     * code in a managed thread.
     *
     * @param func the callback to execute
     * @return value returned by the callback
     */
    protected bool run_task (GLib.SourceFunc func) {
      Threading.Data* data = (Threading.Data*) this.get_private_data ();

      if ( data->threads.contains (GLib.Thread.self<void*> ()) ) {
        GLib.AtomicInt.add (ref data->idle_threads, -1);
        bool res = func ();
        GLib.AtomicInt.inc (ref data->idle_threads);
        return res;
      } else {
        //GLib.warning ("Threading.run_task called from unmanaged thread");
        return func ();
      }
    }

    private void* thread_callback () {
      Threading.Data* internal_data = (Threading.Data*) this.get_private_data ();

      while ( this.process (internal_data->max_idle_time) ) { }

      internal_data->mutex.lock ();
      internal_data->num_threads--;
      if ( !internal_data->threads.remove (GLib.Thread.self<void*> ()) )
        GLib.critical ("Thread was not managed");
      internal_data->mutex.unlock ();

      this.unref ();

      return null;
    }

    /**
     * Because apparently you can't chain up to a virtual interface method
     */
    internal int spawn_internal (int max_new_threads) {
      if ( max_new_threads == 0 )
        return 0;

      int threads_to_spawn = max_new_threads;
      Threading.Data* data = (Threading.Data*) this.get_private_data ();
      GLib.assert (data != null);
      GLib.assert (data->num_threads >= 0);

      if ( data->max_threads == -1 )
        threads_to_spawn -= data->num_threads;
      else
        threads_to_spawn = int.min (threads_to_spawn, data->max_threads - data->num_threads);

      threads_to_spawn -= data->idle_threads;

      if ( threads_to_spawn < 1 )
        return 0;

      data->mutex.lock ();
      if ( data->max_threads != -1 )
        threads_to_spawn = int.min (threads_to_spawn, data->max_threads - data->num_threads);
      data->num_threads += threads_to_spawn;
      data->idle_threads += threads_to_spawn;
      data->mutex.unlock ();

      if ( threads_to_spawn < 1 )
        return 0;

      // GLib.debug ("Spawning %d threads (currently %d / %d threads, %d requested)",
      //             threads_to_spawn, data->num_threads, data->max_threads, max_new_threads);

      string name = "%s[0x%lx]".printf (this.get_type ().name (), (ulong) this);
      for ( int i = 0 ; i < threads_to_spawn ; i++ ) {
        this.ref ();
        GLib.Thread<void*> gthread = new GLib.Thread<void*> (name, this.thread_callback);
        data->threads.add (gthread);
      }

      return threads_to_spawn;
    }

    /**
     * Possibly spawn new thread(s)
     *
     * This method will spawn up to max_new_threads new threads if no
     * constraints (i.e., {@link max_threads}) would be violated by
     * doing so.
     *
     * @param max_new_threads the maximum number of new threads to
     *   spawn, or -1 for unlimited
     * @return the number of new threads spawned
     */
    protected virtual int spawn (int max_new_threads) {
      return this.spawn_internal (max_new_threads);
    }
  }
}
