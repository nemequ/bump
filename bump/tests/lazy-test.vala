private class Resource : GLib.Object {
  public unowned GLib.Thread<void*> initializer = GLib.Thread.self<void*> ();
}

private void test_lazy_sync () {
  Bump.Lazy<Resource> lazy = new Bump.Lazy<Resource> ();

  unowned Resource? res = lazy.get_value ();
  for ( int i = 0 ; i < 16 ; i++ ) {
    if ( res != lazy.get_value () ) {
      GLib.error ("Unexpected change in value");
    }
    if ( res.initializer != GLib.Thread.self<void*> () ) {
      GLib.error ("Resource initialized from a different thread");
    }
  }
}

private async void test_lazy_exec_async () {
  Bump.Lazy<Resource>? lazy = new Bump.Lazy<Resource> ();
  Resource? res = yield lazy.get_value_background ();
  if ( res.initializer == GLib.Thread.self<void*> () ) {
    GLib.error ("Resource not initialized in background");
  }
  for ( int i = 0 ; i < 16 ; i++ ) {
    if ( res != yield lazy.get_value_background () ) {
      GLib.error ("Unexpected change in value");
    }
  }
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
  GLib.Test.add_data_func ("/lazy/async", test_lazy_sync);

  return GLib.Test.run ();
}
