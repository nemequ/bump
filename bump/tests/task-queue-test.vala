/**
 * Make sure callbacks are executed where they are supposed to be.
 */
private void test_task_queue_location () {
  Bump.TaskQueue queue = new Bump.TaskQueue ();
  unowned GLib.Thread<void*> base_thread = GLib.Thread.self<void*> ();

  const int total_test_groups = 8;
  int tests_remaining = total_test_groups * 3;

  for ( int i = 0 ; i < total_test_groups * 3 ; i++ ) {
    switch ( i % 3 ) {
      case 0:
        queue.execute<void*> (() => {
            unowned GLib.Thread<void*> current_thread = GLib.Thread.self<void*> ();
            GLib.assert (base_thread == current_thread);
            tests_remaining--;
            return null;
          });
        break;
      case 1:
        queue.execute_background<void*> (() => {
            unowned GLib.Thread<void*> current_thread = GLib.Thread.self<void*> ();
            GLib.assert (base_thread != current_thread);
            tests_remaining--;
            return null;
          }, GLib.Priority.DEFAULT, null, (obj, res) => {
            unowned GLib.Thread<void*> current_thread = GLib.Thread.self<void*> ();
            GLib.assert (base_thread == current_thread);
          });
        break;
      case 2:
        queue.execute_async<void*> (() => {
            unowned GLib.Thread<void*> current_thread = GLib.Thread.self<void*> ();
            GLib.assert (base_thread == current_thread);
            tests_remaining--;
            return null;
          }, GLib.Priority.DEFAULT, null, (obj, res) => {
            unowned GLib.Thread<void*> current_thread = GLib.Thread.self<void*> ();
            GLib.assert (base_thread == current_thread);
          });
        break;
    }
  }

  GLib.Timeout.add_seconds (1, () => {
      loop.quit ();
      return false;
    });

  loop.run ();

  GLib.assert (tests_remaining == 0);
}

/**
 * Test background tasks
 */
private void test_task_queue_background () {
  Bump.TaskQueue queue = new Bump.TaskQueue ();

  const int total_tasks = 8;
  int tasks_remaining = total_tasks;

  for ( int i = 0 ; i < total_tasks ; i++ ) {
    queue.add (() => {
        GLib.Thread.usleep ((long) GLib.TimeSpan.MILLISECOND * 50);
        tasks_remaining--;

        return false;
      });
  }

  GLib.Timeout.add_seconds (1, () => {
      loop.quit ();
      return false;
    });

  loop.run ();

  GLib.assert (tasks_remaining == 0);
}

public GLib.MainLoop loop;

private static int main (string[] args) {
  GLib.Test.init (ref args);

  loop = new GLib.MainLoop ();

  GLib.Test.add_data_func ("/task-queue/location", test_task_queue_location);
  GLib.Test.add_data_func ("/task-queue/background", test_task_queue_background);

  return GLib.Test.run ();
}
