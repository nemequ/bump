namespace Bump {
  /**
   * Queue of callbacks
   *
   * This basically just provides common code to TaskQueue and Event.
   */
  internal class CallbackQueue<G> : GLib.Object {
    internal abstract class Data {
      public unowned Bump.CallbackQueue<Bump.CallbackQueue.Data>? owner;
      public int priority;
      public int age;
      public GLib.Cancellable? cancellable;
      public ulong cancellable_id;

      public void queue () {
        this.owner.requeue (this);
      }

      public void connect_cancellable () {
        if ( this.cancellable != null ) {
          if ( this.cancellable_id != 0 ) {
            this.disconnect_cancellable ();
          }

          this.cancellable_id = this.cancellable.connect ((c) => {
              this.owner.remove (this);
            });
        }
      }

      public void disconnect_cancellable () {
        if ( this.cancellable != null && this.cancellable_id != 0 ) {
          this.cancellable.disconnect (this.cancellable_id);
          this.cancellable_id = 0;
        }
      }

      public static int compare (CallbackQueue.Data? a, CallbackQueue.Data? b) {
        int res = a.priority - b.priority;
        return (res != 0) ? res : a.age - b.age;
      }
    }

    public int length {
      get {
        return this.queue.size;
      }
    }

    public int waiting_threads {
      get {
        return this.queue.waiting_threads;
      }
    }

    /**
     * The actual queue
     */
    private Bump.AsyncPriorityQueue<CallbackQueue.Data> queue;

    /**
     * Number of items that have been added to the queue
     *
     * This is used to make sure operations with the same priority are
     * executed in the order received
     */
    private int _age = 0;

    /**
     * Atomically increment the age, returning the old value
     */
    private int increment_age () {
      return GLib.AtomicInt.add (ref this._age, 1);
    }

    public G? peek_timed (GLib.TimeSpan wait = -1) {
      return this.queue.peek_timed (wait);
    }

    public G? peek () {
      return this.queue.peek ();
    }

    public G? poll_timed (GLib.TimeSpan wait = -1) {
      return this.queue.poll_timed (wait);
    }

    public bool foreach (Gee.ForallFunc<G> f) {
      return this.queue.foreach ((d) => { return f (d); });
    }

    public G[] to_array () {
      return (G[]) this.queue.to_array ();
    }

    public bool remove (G element) {
      return this.queue.remove ((CallbackQueue.Data) element);
    }

    public signal void consumer_shortage ();

    /**
     * Add the item to the queue
     *
     * This will assume that the data is properly configured (the
     * cancellable is connected, owner is set, etc.).
     */
    internal void requeue (Bump.CallbackQueue.Data data) {
      data.age = this.increment_age ();
      this.queue.offer (data);
    }

    /**
     * Add (or re-add) to queue
     */
    public void offer (G data) {
      unowned CallbackQueue.Data d = (CallbackQueue.Data) data;
      if ( d.cancellable == null || !d.cancellable.is_cancelled () ) {
        if ( d.owner != this ) {
          d.owner = (Bump.CallbackQueue<Bump.CallbackQueue.Data>) this;
        }
        this.requeue (d);
        if ( d.cancellable_id == 0 )
          d.connect_cancellable ();
      }
    }

    construct {
      this.queue = new Bump.AsyncPriorityQueue<CallbackQueue.Data> (CallbackQueue.Data.compare);
      this.queue.consumer_shortage.connect (() => { this.consumer_shortage (); });
    }
  }
}
