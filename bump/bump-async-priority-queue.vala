namespace Bump {
  /**
   * Priority queue for asynchronous communications
   *
   * This is basically just a layer on top of GeePriorityQueue to
   * provide thread safety and blocking peek and poll methods, similar
   * to how GAsyncQueue adds functionality to GQueue.
   */
  public class AsyncPriorityQueue<G> : Gee.PriorityQueue<G> {
    private GLib.Cond cond = GLib.Cond ();
    private GLib.Mutex mutex = GLib.Mutex ();

    public int waiting_threads { get; private set; }

    /**
     * Poll the queue, blocking until timeout or data is received
     *
     * @param wait the duration to wait. 0 for no waiting, -1 to wait
     *   forever
     * @return the data, or null if there was no data
     */
    public G? poll_timed (GLib.TimeSpan wait = -1) {
      int64 until = (wait > 0) ? GLib.get_monotonic_time () + wait : wait;
      G? data = null;

      this.mutex.lock ();
      this.waiting_threads++;

      while ( (data = base.poll ()) == null ) {
        if ( until < 0 ) {
          this.cond.wait (this.mutex);
        } else if ( until > 0 ) {
          if ( !this.cond.wait_until (this.mutex, until) ) {
            break;
          }
        } else {
          break;
        }
      }

      this.waiting_threads--;
      this.mutex.unlock ();

      return data;
    }

    public override G? poll () {
      return this.poll_timed (-1);
    }
    /**
     * Peek on the queue, blocking until timeout or data is received
     *
     * @param wait the duration to wait. 0 for no waiting, -1 to wait
     *   forever
     * @return the data, or null if there was no data
     */
    public G? peek_timed (GLib.TimeSpan wait = -1) {
      int64 until = (wait > 0) ? GLib.get_monotonic_time () + wait : wait;
      G? data = null;

      this.mutex.lock ();
      this.waiting_threads++;

      while ( (data = base.peek ()) == null ) {
        if ( until < 0 ) {
          this.cond.wait (this.mutex);
        } else if ( until > 0 ) {
          if ( !this.cond.wait_until (this.mutex, until) ) {
            break;
          }
        } else {
          break;
        }
      }

      this.waiting_threads--;
      this.mutex.unlock ();

      return data;
    }

    public override G? peek () {
      return this.peek_timed (-1);
    }

    public new bool offer (G element) {
      bool emit_shortage = false;

      this.mutex.lock ();
      bool r = base.offer (element);
      if ( this.waiting_threads == 0 )
        emit_shortage = true;
      else
        this.cond.signal ();
      this.mutex.unlock ();

      this.consumer_shortage ();

      return r;
    }

    public override bool foreach (Gee.ForallFunc<G> f) {
      this.mutex.lock ();
      try {
        return base.foreach ((d) => { return f (d); });
      } finally {
        this.mutex.unlock ();
      }
    }

    /**
     * Data was added to the queue but no consumers were waiting.
     */
    public signal void consumer_shortage ();

    public AsyncPriorityQueue (owned GLib.CompareDataFunc? compare_func = null) {
      base ((owned) compare_func);
    }
  }
}

#if BUMP_TEST_ASYNC_PRIORITY_QUEUE
private static int main (string[] args) {
  var q = new Tumbler.AsyncPriorityQueue<string> ();
  string r;
  q.offer ("one");
  q.offer ("two");
  q.offer ("three");
  while ( (r = q.peek_timed (GLib.TimeSpan.SECOND * 10)) != null ) {
    GLib.debug (q.try_poll ());
  }

  return 0;
}
#endif
