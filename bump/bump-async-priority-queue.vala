namespace Bump {
  /**
   * Priority queue for asynchronous communications
   *
   * This is basically just a layer on top of GeePriorityQueue to
   * provide thread safety and blocking peek and poll methods, similar
   * to how GAsyncQueue adds functionality to GQueue.
   */
  public class AsyncPriorityQueue<G> : Gee.PriorityQueue<G> {
    private GLib.Cond cond = new GLib.Cond ();
    private GLib.Mutex mutex = new GLib.Mutex ();

    public int waiting_threads { get; private set; }

    private G? poll_timed_internal (GLib.TimeVal? until = null) {
      this.mutex.lock ();
      this.waiting_threads++;

      G? data = null;

      if ( (data = base.poll ()) == null ) {
        while ( (data = base.poll ()) == null ) {
          if ( until == null ) {
            this.cond.wait (this.mutex);
          } else {
            if ( !this.cond.timed_wait (this.mutex, until) ) {
              break;
            }
          }
        }
      }

      this.waiting_threads--;
      this.mutex.unlock ();

      return data;
    }

    /**
     * Poll the queue, giving up after the specified time span
     *
     * @param wait number of microseconds to wait
     * @return the data, or null if the time was exceeded
     */
    public virtual G? poll_timed (GLib.TimeSpan wait = -1) {
      if ( wait > 0 ) {
        GLib.TimeVal tv = GLib.TimeVal ();
        tv.get_current_time ();
        tv.add ((long) wait);
        return this.poll_timed_internal (tv);
      } else if ( wait < 0 ) {
        return this.poll_timed_internal (null);
      } else {
        return this.try_poll ();
      }
    }

    public override G? poll () {
      return this.poll_timed_internal (null);
    }

    /**
     * Poll the queue without blocking
     *
     * @return the data, or null if there was no data
     */
    public virtual G? try_poll () {
      G? data = null;
      this.mutex.lock ();
      data = base.poll ();
      this.mutex.unlock ();
      return data;
    }

    private G? peek_timed_internal (GLib.TimeVal? until = null) {
      this.mutex.lock ();
      this.waiting_threads++;

      G? data = null;

      if ( (data = base.peek ()) == null ) {
        while ( (data = base.peek ()) == null ) {
          if ( until == null ) {
            this.cond.wait (this.mutex);
          } else {
            if ( !this.cond.timed_wait (this.mutex, until) ) {
              break;
            }
          }
        }
      }

      this.waiting_threads--;
      this.mutex.unlock ();

      return data;
    }

    /**
     * Peek the queue, giving up after the specified time span
     *
     * @param wait number of microseconds to wait
     * @return the data, or null if the time was exceeded
     */
    public virtual G? peek_timed (GLib.TimeSpan wait = -1) {
      if ( wait > 0 ) {
        GLib.TimeVal tv = GLib.TimeVal ();
        tv.get_current_time ();
        tv.add ((long) wait);
        return this.peek_timed_internal (tv);
      } else if ( wait < 0 ) {
        return this.peek ();
      } else {
        return this.try_peek ();
      }
    }

    public override G? peek () {
      return this.peek_timed_internal (null);
    }

    /**
     * Peek the queue without blocking
     *
     * @return the data, or null if there was no data
     */
    public virtual G? try_peek () {
      G? data = null;
      this.mutex.lock ();
      data = base.peek ();
      this.mutex.unlock ();
      return data;
    }

    public override bool offer (G element) {
      this.mutex.lock ();
      bool r = base.offer (element);
      this.cond.signal ();
      this.mutex.unlock ();
      return r;
    }

    public override bool remove (G element) {
      this.mutex.lock ();
      bool r = base.remove (element);
      this.mutex.unlock ();
      return r;
    }

    public AsyncPriorityQueue (owned GLib.CompareFunc? compare_func = null) {
      base (compare_func);
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
