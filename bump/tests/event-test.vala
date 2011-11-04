private async void test_event_execute_async_parallel_async (GLib.MainLoop loop) {
  string argument = "Foo";
  Bump.Event<string> evt = new Bump.Event<string> ();

  int remaining = 128;

  for ( int i = 0 ; i < 128 ; i++ ) {
    evt.execute_async<string> ((arg) => {
        return arg;
      }, GLib.Priority.DEFAULT, null, (o, async_res) => {
        GLib.assert (evt.execute_async.end<string> (async_res) == argument);
        if ( --remaining == 0 ) {
          loop.quit ();
        }
      });
  }

  evt.trigger (argument);
}

/**
 * Make sure the async execute* work correctly with multiple listeners
 */
private void test_event_execute_async_parallel () {
  GLib.MainLoop loop = new GLib.MainLoop ();

  test_event_execute_async_parallel_async (loop);

  if ( GLib.Test.trap_fork (GLib.TimeSpan.SECOND, GLib.TestTrapFlags.SILENCE_STDOUT | GLib.TestTrapFlags.SILENCE_STDERR) ) {
    loop.run ();
    GLib.Process.exit (0);
  }
  GLib.Test.trap_assert_passed ();
}

private async void test_event_execute_async_sequential_async () {
  string argument = "Foo";
  Bump.Event<int> evt = new Bump.Event<int> ();

  for ( int i = 0 ; i < 8 ; i++ ) {
    int x = i;

    GLib.Timeout.add (10, () => {
        evt.trigger (x);
        return false;
      });

    string ret = yield evt.execute_async<string> ((arg) => {
        GLib.assert (arg == x);
        return argument;
      });
    GLib.assert (ret == argument);
  }
}

/**
 * Make sure the async execute* work correctly
 */
private void test_event_execute_async_sequential () {
  GLib.MainLoop loop = new GLib.MainLoop ();

  test_event_execute_async_sequential_async ((o, async_res) => {
      loop.quit ();
    });

  if ( GLib.Test.trap_fork (GLib.TimeSpan.SECOND, GLib.TestTrapFlags.SILENCE_STDOUT | GLib.TestTrapFlags.SILENCE_STDERR) ) {
    loop.run ();
    GLib.Process.exit (0);
  }
  GLib.Test.trap_assert_passed ();
}

/**
 * Test blocking execute
 */
private void test_event_execute () {
  Bump.Event<string> evt = new Bump.Event<string> ();
  string argument = "Foo";

  if ( GLib.Test.trap_fork (GLib.TimeSpan.SECOND, GLib.TestTrapFlags.SILENCE_STDOUT | GLib.TestTrapFlags.SILENCE_STDERR) ) {
    unowned GLib.Thread<string> thread = GLib.Thread.create<string> (() => {
        string res = evt.execute<string> ((arg) => {
            GLib.debug (arg);
            return arg;
          });
        return res;
      }, true);
    // Make sure we connect before triggering the event
    GLib.Thread.usleep ((long) GLib.TimeSpan.SECOND / 10);

    evt.trigger (argument);
    GLib.assert (thread.join () == argument);
    GLib.Process.exit (0);
  }
  GLib.Test.trap_assert_passed ();
}

/**
 * Make sure arguments and return values work as expected
 */
private void test_event_data () {
  GLib.MainLoop loop = new GLib.MainLoop ();
  Bump.Event<string> evt = new Bump.Event<string> ();
  string argument = "Foo";
  int outstanding_tasks = 3;

  evt.add ((arg) => {
      GLib.assert (arg == argument);

      if ( GLib.AtomicInt.dec_and_test (ref outstanding_tasks) )
        loop.quit ();

      return false;
    });

  evt.execute_async<string> ((arg) => {
      GLib.assert (arg == argument);

      return arg;
    }, GLib.Priority.DEFAULT, null, (o, async_res) => {
      GLib.assert (evt.execute_async.end<string> (async_res) == argument);

      if ( GLib.AtomicInt.dec_and_test (ref outstanding_tasks) )
        loop.quit ();
    });

  evt.execute_background<string> ((arg) => {
      GLib.assert (arg == argument);

      return arg;
    }, GLib.Priority.DEFAULT, null, (o, async_res) => {
      GLib.assert (evt.execute_async.end<string> (async_res) == argument);

      if ( GLib.AtomicInt.dec_and_test (ref outstanding_tasks) )
        loop.quit ();
    });

  GLib.Idle.add (() => {
      evt.trigger (argument);
      return false;
    });

  if ( GLib.Test.trap_fork (GLib.TimeSpan.SECOND, GLib.TestTrapFlags.SILENCE_STDOUT | GLib.TestTrapFlags.SILENCE_STDERR) ) {
    loop.run ();
    GLib.Process.exit (0);
  }
  GLib.Test.trap_assert_passed ();
}

private static int main (string[] args) {
  GLib.Test.init (ref args);

  GLib.Test.add_data_func ("/event/data", test_event_data);
  GLib.Test.add_data_func ("/event/execute", test_event_execute);
  GLib.Test.add_data_func ("/event/execute_async/sequential", test_event_execute_async_sequential);
  GLib.Test.add_data_func ("/event/execute_async/parallel", test_event_execute_async_parallel);

  return GLib.Test.run ();
}
