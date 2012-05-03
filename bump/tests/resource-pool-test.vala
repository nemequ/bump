private void test_resource_pool_acquire () {
  Bump.ResourcePool<Bump.Semaphore> pool = new Bump.ResourcePool<Bump.Semaphore> ();

  try {
    Bump.Semaphore sem = pool.acquire ();
    GLib.assert (sem is Bump.Semaphore);
    pool.release (sem);
  } catch ( GLib.Error e ) {
    GLib.error (e.message);
  }
}

private void test_resource_pool_recycle () {
  int i = 0;
  Bump.ResourcePool<Bump.Semaphore> pool = new Bump.ResourcePool<Bump.Semaphore> ();
  unowned Bump.Semaphore? sem = null;

  GLib.HashTable<unowned Bump.Semaphore,unowned Bump.Semaphore> ht =
    new GLib.HashTable<unowned Bump.Semaphore,unowned Bump.Semaphore> (GLib.direct_hash, GLib.direct_equal);

  for ( i = 0 ; i < 32 ; i++ ) {
    try {
      sem = pool.acquire ();
    } catch ( GLib.Error e ) {
      GLib.error (e.message);
    }
    ht[sem] = sem;
  }

  ht.foreach ((k, v) => { pool.release (k); });

  for ( i = 0 ; i < 32 ; i++ ) {
    try {
      sem = pool.acquire ();
    } catch ( GLib.Error e ) {
      GLib.error (e.message);
    }
    GLib.assert (ht[sem] == sem);
    ht.remove (sem);
  }
}

private void test_resource_pool_cleanup () {
  int i = 0;
  Bump.ResourcePool<Bump.Semaphore> pool = new Bump.ResourcePool<Bump.Semaphore> ();
  unowned Bump.Semaphore? sem = null;

  pool.max_idle_time = GLib.TimeSpan.SECOND;

  GLib.HashTable<unowned Bump.Semaphore,unowned Bump.Semaphore> ht =
    new GLib.HashTable<unowned Bump.Semaphore,unowned Bump.Semaphore> (GLib.direct_hash, GLib.direct_equal);

  for ( i = 0 ; i < 32 ; i++ ) {
    try {
      sem = pool.acquire ();
    } catch ( GLib.Error e ) {
      GLib.error (e.message);
    }
    ht[sem] = sem;
  }
  ht.foreach ((k, v) => { pool.release (k); });

  GLib.Timeout.add_seconds (3, () => {
      GLib.assert (pool.num_resources == 0);
      loop.quit ();
      return false;
    });

  loop.run ();
}

private void test_resource_pool_max_resources () {
  Bump.ResourcePool<Bump.Semaphore> pool = new Bump.ResourcePool<Bump.Semaphore> (1);

  int iterations = 8;
  int active = 0;
  int completed = 0;

  unowned Bump.Semaphore? sem = null;

  for ( int i = 0 ; i < iterations ; i++ ) {
    pool.execute_background<void*> ((resource) => {
        GLib.AtomicInt.add (ref active, 1);

        if ( sem == null )
          sem = resource;
        else {
          if ( sem != resource )
            GLib.error ("Got a a different resource (0x%lx) than expected (0x%lx)", (ulong) sem, (ulong) resource);
        }

        if ( pool.num_resources != 1) {
          GLib.error ("%d resource in the pool, expected 1", pool.num_resources);
        }

        GLib.Thread.usleep ((long) GLib.TimeSpan.MILLISECOND * 50);

        GLib.AtomicInt.add (ref completed, 1);
        GLib.assert (GLib.AtomicInt.dec_and_test (ref active));

        if ( completed == iterations ) {
          GLib.Timeout.add (100, () => {
              loop.quit ();
              return false;
            });
        } else if ( completed > iterations ) {
          GLib.error ("Executed extra iterations");
        }

        return null;
      });
  }

  loop.run ();

  GLib.assert (active == 0);
  GLib.assert (completed == iterations);
}

public GLib.MainLoop loop;

private static int main (string[] args) {
  GLib.Test.init (ref args);

  loop = new GLib.MainLoop ();

  GLib.Test.add_data_func ("/resource-pool/acquire", test_resource_pool_acquire);
  GLib.Test.add_data_func ("/resource-pool/recycle", test_resource_pool_recycle);
  GLib.Test.add_data_func ("/resource-pool/max_resources", test_resource_pool_max_resources);
  GLib.Test.add_data_func ("/resource-pool/cleanup", test_resource_pool_cleanup);

  return GLib.Test.run ();
}

