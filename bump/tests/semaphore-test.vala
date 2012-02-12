/**
 * Test background tasks
 */
private void test_semaphore_binary () {
  Bump.Semaphore sem = new Bump.Semaphore (1);

  bool active = false;
  int iterations = 8;

  for ( int i = 0 ; i < iterations ; i++ ) {
    int x = i;
    sem.execute_background<void*> (() => {
        if ( active == true ) {
          GLib.error ("Multiple active callbacks");
        }
        active = true;
        GLib.Thread.usleep ((ulong) GLib.TimeSpan.MILLISECOND * 10);
        active = false;

        if ( x >= (iterations - 1) )
          loop.quit ();

        return null;
      });
  }

  loop.run ();
}

private void test_semaphore_counting () {
  int N = 8;
  int tasks = N * 8;
  Bump.Semaphore sem = new Bump.Semaphore (1);

  int active = 0;
  int remaining = tasks;

  for ( int i = remaining ; i > 0 ; i-- ) {
    sem.execute_background<void*> (() => {
        GLib.AtomicInt.add (ref active, 1);
        int wait = (int) ((GLib.Random.next_int () & 63) + 1);
        GLib.Thread.usleep ((long) GLib.TimeSpan.MILLISECOND * wait);
        GLib.assert (active > 0 && active <= N);
        GLib.AtomicInt.dec_and_test (ref active);
        if ( GLib.AtomicInt.dec_and_test (ref remaining) ) {
          loop.quit ();
        }

        return null;
      });
  }

  loop.run ();

  GLib.assert (active == 0);
  GLib.assert (remaining == 0);
}

private GLib.MainLoop loop;

private static int main (string[] args) {
  GLib.Test.init (ref args);

  loop = new GLib.MainLoop ();

  GLib.Test.add_data_func ("/semaphore/binary", test_semaphore_binary);
  GLib.Test.add_data_func ("/semaphore/counting", test_semaphore_counting);

  return GLib.Test.run ();
}
