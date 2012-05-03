private void test_claim_basic () {
  const int claims_count = 8;
  Bump.Semaphore sem = new Bump.Semaphore (claims_count * 2);
  GLib.SList<Bump.Claim> claims = new GLib.SList<Bump.Claim> ();

  for ( int i = 0 ; i < claims_count ; i++ ) {
    try {
      claims.prepend (sem.claim ());
    } catch ( GLib.Error e ) {
      GLib.error (e.message);
    }
  }

  if ( sem.claims != 8 )
    GLib.error ("Expected %d claims, got %d", 8, sem.claims);
}

private void test_claim_reporting () {
  try {
    Bump.Semaphore sem = new Bump.Semaphore (1);
    Bump.Claim claim = sem.claim ();

    GLib.Thread.usleep ((long) GLib.TimeSpan.MILLISECOND * 9);
    claim.release ();

    if ( claim.duration_held != claim.duration_held )
      GLib.error ("Claim clock is still going");
    // else if ( claim.duration_held > GLib.TimeSpan.MILLISECOND * 10 )
    //   GLib.error ("Claim held for longer than expected (%lld, expected between %lld and %lld)",
    //               claim.duration_held, GLib.TimeSpan.MILLISECOND * 9, GLib.TimeSpan.MILLISECOND * 10);
  } catch ( GLib.Error e ) {
    GLib.error (e.message);
  }
}

private void test_claim_resource_pool () {
  Bump.ResourcePool<Bump.Semaphore> pool = new Bump.ResourcePool<Bump.Semaphore> (1);

  int iterations = 8;
  int active = 0;
  int completed = 0;

  unowned Bump.Semaphore? sem = null;

  for ( int i = 0 ; i < iterations ; i++ ) {
    try {
      GLib.AtomicInt.add (ref active, 1);

      Bump.ResourceClaim<Bump.Semaphore> claim = pool.claim ();
      unowned Bump.Semaphore? resource = claim.resource;

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
    } catch ( GLib.Error e ) {
      GLib.error (e.message);
    }
  }

  loop.run ();

  GLib.assert (active == 0);
  GLib.assert (completed == iterations);
}

private GLib.MainLoop loop;

private static int main (string[] args) {
  GLib.Test.init (ref args);

  loop = new GLib.MainLoop ();

  GLib.Test.add_data_func ("/claim/basic", test_claim_basic);
  GLib.Test.add_data_func ("/claim/reporting", test_claim_reporting);
  GLib.Test.add_data_func ("/claim/resource_pool", test_claim_resource_pool);

  return GLib.Test.run ();
}
