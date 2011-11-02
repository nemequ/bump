namespace Bump {
  /**
   * An event
   *
   * An event is a bit like a signal where all handlers are dispatched
   * immediately. In other words, as soon as the event is triggered,
   * all background tasks will be passed to the {@link pool}, all idle
   * callback tasks will be added to the idle queue, and all blocking
   * tasks will be woken.
   *
   * An interesting side-effect of this is that Event.SourceFunc
   * callbacks can be executed after they return false, since other
   * events may have caused the callback to be queued again. If you
   * want to make sure that a callback is not invoked again you should
   * use the cancellable.
   */
  public class Event<T> : GLib.Object {
    /**
     * Callback for use with {@link Event.execute} and variants
     *
     * @param argument passed when triggering the event
     * @return whatever you want
     */
    public delegate R Callback<A,R> (A arg) throws GLib.Error;

    /**
     * Callback for use with {@link Event.add}
     *
     * The callback will be dispatched for each event, until it
     * returns false
     *
     * @param argument passed when triggering the event
     * @return whatever you want
     */
    public delegate bool SourceFunc<A> (A arg);

    internal class Data<A> : CallbackQueue.Data {
      /**
       * The task to be executed
       */
      public Bump.Event.SourceFunc<A>? task;

      /**
       * Trigger the callback
       *
       * @return whether to requeue the data
       */
      public bool trigger (A arg) {
        GLib.debug ("Invoking callback (0x%lx)...", (ulong) this.task);
        var r = this.task (arg);
        GLib.debug ("Callback invoked");
        return r;
      }
    }

    private Bump.CallbackQueue<Bump.Event.Data<T>> queue =
      new Bump.CallbackQueue<Bump.Event.Data<T>> ();

    /**
     * The pool used to execute background tasks
     */
    public Bump.ThreadPool pool { get; construct; }

    /**
     * Whether to automatically reset the event after dispatching the
     * handlers
     */
    public bool auto_reset { get; construct; default = true; }

    /**
     * Whether or not the event is currently triggered
     */
    public bool triggered { get; private set; }

    public void reset () {
      lock ( this.triggered ) {
        this.triggered = false;
      }
    }

    /**
     * Trigger the event
     *
     * @param value the value to pass to each listener
     */
    public void trigger (T value) throws GLib.Error {
      lock ( this.triggered ) {
        this.triggered = true;

        foreach ( unowned Bump.Event.Data<T> data in this.queue.to_array () ) {
          if ( GLib.unlikely (!data.trigger (value)) ) {
            this.queue.remove (data);
          }
        }

        this.triggered = false;
      }
    }

    /**
     * Create a new data structure
     *
     * @param priority the priority of the callback
     * @param cancellable optional cancellable
     */
    private Bump.Event.Data<T> prepare (int priority = GLib.Priority.DEFAULT, GLib.Cancellable? cancellable = null) throws GLib.Error {
      Bump.Event.Data<T> data = new Bump.Event.Data<T> ();
      data.priority = priority;
      data.cancellable = cancellable;

      return data;
    }

    /**
     * Add a callback to be executed in the idle queue
     *
     * The callback will be added to the idle queue once per event
     * until it returns false. Note that this means it is possible
     * that the callback will be executed again after it returns
     * false, since another event could be triggered (causing the
     * callback to be added to the idle queue again) before the
     * callback is actually executed.
     *
     * @param func the callback to add
     * @param priority the priority of the callback
     * @param optional cancellable for removing the callback
     */
    public void add (owned Bump.Event.SourceFunc<T> func, int priority = GLib.Priority.DEFAULT, GLib.Cancellable? cancellable = null) throws GLib.Error {
      Bump.Event.Data<T> data = this.prepare (priority, cancellable);
      data.task = (arg) => {
        var id = GLib.Idle.add (() => {
            if ( !func (arg) ) {
              this.queue.remove (data);
            }

            return false;
          });

        return true;
      };
      this.queue.offer (data);
    }

    /**
     * Execute the callback and wait for the result
     *
     * This method will block until the event is triggered, then
     * execute the callback and return the result
     *
     * @param func the callback to execute once the event is triggered
     * @param priority the priority of the callback
     * @param cancellable optional cancellable for aborting
     */
    public R execute<R> (Bump.Event.Callback<T,R> func, int priority = GLib.Priority.DEFAULT, GLib.Cancellable? cancellable = null) throws GLib.Error {
      T argument = null;
      GLib.Mutex sync = new GLib.Mutex ();
      sync.lock ();

      if ( cancellable != null ) {
        cancellable.connect ((c) => {
            sync.unlock ();
          });
      }

      Bump.Event.Data<T> data = this.prepare (priority, cancellable);
      data.task = (arg) => {
        argument = arg;
        sync.unlock ();

        return false;
      };
      this.queue.offer (data);

      sync.lock ();

      if ( cancellable != null )
        cancellable.set_error_if_cancelled ();

      return func (argument);
    }

    /**
     * Execute the callback asynchronously
     *
     * This method will wait until the event is triggered, then
     * execute the (as an idle callback) callback and return the
     * result.
     *
     * @param func the callback to execute once the event is triggered
     * @param priority the priority of the callback
     * @param cancellable optional cancellable for aborting
     */
    public async R execute_async<R> (Bump.Event.Callback<T,R> func, int priority = GLib.Priority.DEFAULT, GLib.Cancellable? cancellable = null) throws GLib.Error {
      T argument = null;
      Bump.Event.Data<T> data = this.prepare (priority, cancellable);
      data.task = (arg) => {
        argument = arg;
        GLib.Idle.add_full (priority, this.execute_async.callback);
        return false;
      };
      this.queue.offer (data);
      yield;

      return func (argument);
    }

    /**
     * Execute the callback asynchronously
     *
     * This method will wait until the event is triggered, then
     * execute the callback in a thread (from the {@link pool}) and
     * return the result asynchronously.
     *
     * @param func the callback to execute once the event is triggered
     * @param priority the priority of the callback
     * @param cancellable optional cancellable for aborting
     */
    public async R execute_background<R> (Bump.Event.Callback<T,R> func, int priority = GLib.Priority.DEFAULT, GLib.Cancellable? cancellable = null) throws GLib.Error {
      R retval = null;
      Bump.Event.Data<T> data = this.prepare (priority, cancellable);
      data.task = (arg) => {
        this.pool.add (() => {
            GLib.error ("https://bugzilla.gnome.org/show_bug.cgi?id=663210");
            //retval = func (arg);

            return false;
          }, priority, cancellable);
        return false;
      };
      this.queue.offer (data);
      yield;

      return retval;
    }


    construct {
      if ( this.pool == null ) {
        this.pool = Bump.ThreadPool.get_global (0);
      }
    }

    /**
     * Create a new Event
     *
     * @param auto_reset whether to automatically reset the event
     *   after the handlers have been invoked
     * @param pool the pool to use to execute background tasks, or
     *   null for the default
     */
    public Event (bool auto_reset = true, Bump.ThreadPool? pool = null) {
      GLib.Object (auto_reset: auto_reset, pool: pool);
    }
  }
}

#if BUMP_TEST_EVENT

public async void test_execute_background (Bump.Event<string> evt, GLib.MainLoop loop) {
  GLib.debug ("Beginning background test");
  string res = yield evt.execute_background<string> ((arg) => {
      GLib.debug ("From execute_background callback: %s", arg);
      return "Baz";
    });
  GLib.debug ("From execute_background: %s", res);
}

public async void test_execute_async (Bump.Event<string> evt, GLib.MainLoop loop) {
  GLib.debug ("Beginning idle test");
  string res = yield evt.execute_async<string> ((arg) => {
      GLib.debug ("From execute_async callback: %s", arg);
      return "Baz";
    });
  GLib.debug ("From execute_async: %s", res);
}

private static int main (string[] args) {
  GLib.MainLoop loop = new GLib.MainLoop ();
  Bump.Event<string> evt = new Bump.Event<string> ();

  evt.add ((arg) => {
      GLib.debug ("From add: %s", arg);
      return false;
    });
  GLib.Thread.create<void*> (() => {
      string res = evt.execute<string> ((arg) => {
            GLib.debug ("From execute callback: %s", arg);
            return "Bar";
        });
      GLib.debug ("From execute: %s", res);
      return null;
    }, false);
  //test_execute_background.begin (evt, loop);
  test_execute_async.begin (evt, loop);


  GLib.Timeout.add_seconds (1, () => {
      evt.trigger ("Foo");
      return false;
    });

  GLib.Timeout.add_seconds (3, () => { loop.quit (); return true; });

  loop.run ();
  // GLib.Thread.create<void*> (() => {
  //     GLib.debug (evt.execute<string> ((s) => {
  //           return s;
  //         }));

  //     return null;
  //   }, false);
  // GLib.Thread.usleep ((ulong) GLib.TimeSpan.SECOND);
  // evt.trigger ("Hello, world!");
  // GLib.Thread.usleep ((ulong) GLib.TimeSpan.SECOND * 4);

  return 0;
}

#endif
