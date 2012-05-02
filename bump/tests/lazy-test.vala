private class Resource : GLib.Object {
  public unowned GLib.Thread<void*> initializer = GLib.Thread.self<void*> ();
}

private void test_lazy_sync () {
  Bump.Lazy<Resource> lazy = new Bump.Lazy<Resource> ();

  unowned Resource? res = lazy.acquire ();
  for ( int i = 0 ; i < 16 ; i++ ) {
    if ( res != lazy.acquire () ) {
      GLib.error ("Unexpected change in value");
    }
    if ( res.initializer != GLib.Thread.self<void*> () ) {
      GLib.error ("Resource initialized from a different thread");
    }
  }
}

private async void test_lazy_exec_async () {
  Bump.Lazy<Resource>? lazy = new Bump.Lazy<Resource> ();
  Resource? res = yield lazy.acquire_background ();
  if ( res.initializer == GLib.Thread.self<void*> () ) {
    GLib.error ("Resource not initialized in background");
  }
  for ( int i = 0 ; i < 16 ; i++ ) {
    if ( res != yield lazy.acquire_background () ) {
      GLib.error ("Unexpected change in value");
    }
  }
}

private class DelayedResource : GLib.Object {
  construct {
    GLib.Thread.usleep ((ulong) GLib.TimeSpan.MILLISECOND * 1000);
  }
}

private void test_lazy_concurrent () {
  Bump.Lazy<DelayedResource> lazy = new Bump.Lazy<DelayedResource> ();
  const int n = 16;
  int remaining = n;
  Bump.TaskQueue pool = Bump.TaskQueue.get_global ();
  unowned DelayedResource? res = null;

  GLib.Thread.usleep ((ulong) GLib.TimeSpan.MILLISECOND * 100);

  for ( int i = 0 ; i < n ; i++ ) {
    int x = i;
    // I'm using GLib.Thread directly here instead of a Bump.TaskQueue
    // for testing purposes only. I want to make sure to launch one
    // thread per item, and never recycle the thread.
    new GLib.Thread<void*> ("concurrent#%d".printf (x), () => {
        unowned DelayedResource? r = lazy.acquire ();

        if ( res != null && r != res ) {
          GLib.error ("Unexpected change in value");
        }

        if ( GLib.AtomicInt.dec_and_test (ref remaining) ) {
          loop.quit ();
        }

        return null;
      });
  }
  loop.run ();
}

private void test_lazy_async () {
  test_lazy_exec_async ((o, async_res) => {
      loop.quit ();
    });
  loop.run ();
}

public GLib.MainLoop loop;

private static int main (string[] args) {
  GLib.Test.init (ref args);

  loop = new GLib.MainLoop ();

  GLib.Test.add_data_func ("/lazy/sync", test_lazy_sync);
  GLib.Test.add_data_func ("/lazy/async", test_lazy_async);
  GLib.Test.add_data_func ("/lazy/concurrent", test_lazy_concurrent);

  return GLib.Test.run ();
}
