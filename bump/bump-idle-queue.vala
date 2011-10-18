namespace Bump {
  /**
   * A TaskQueue which uses a GLib idle callback to process tasks.
   *
   * A single idle callback is added to GLib to process this queue so
   * long as tasks remain to be processed.
   */
  public class IdleQueue : Bump.TaskQueue {
    private uint source_id = 0;

    private int _idle_callback_priority = GLib.Priority.DEFAULT_IDLE;

    /**
     * The priority for the GLib idle callback
     *
     * The idle callback used to process this queue is uses this value
     * for the priority. This means that anything added directly to
     * GLib with a priority higher than this value will preempt all
     * tasks in this queue, and any task in this queue will prempt all
     * tasks in GLib with a priority lower than this value.
     *
     * The default value is DEFAULT_IDLE.
     */
    public int idle_callback_priority {
      get {
        return this._idle_callback_priority;
      }

      construct set {
        this._idle_callback_priority = value;

        if ( this.source_id != 0 ) {
          lock ( this.source_id ) {
            if ( this.source_id != 0 ) {
              GLib.Source.remove (this.source_id);
              GLib.Idle.add (this.idle_callback, this.idle_callback_priority);
            }
          }
        }
      }
    }

    private bool idle_callback () {
      if ( this.process () ) {
        return true;
      } else {
        lock ( this.source_id ) {
          this.source_id = 0;
        }
        return false;
      }
    }

    public override void add (owned GLib.SourceFunc task, int priority = GLib.Priority.DEFAULT, GLib.Cancellable? cancellable = null) throws GLib.Error {
      base.add (() => { return task (); }, priority, cancellable);

      if ( this.source_id == 0 ) {
        lock ( this.source_id ) {
          if ( this.source_id == 0 ) {
            GLib.Idle.add (this.idle_callback, this.idle_callback_priority);
          }
        }
      }
    }
  }
}

#if BUMP_TEST_IDLE_QUEUE
private static int main (string[] args) {
  GLib.MainLoop loop = new GLib.MainLoop ();
  Bump.IdleQueue q = new Bump.IdleQueue ();
  q.add (() => { GLib.debug ("World"); loop.quit (); return false; }, GLib.Priority.LOW);
  q.add (() => { GLib.debug ("Hello"); return false; }, GLib.Priority.HIGH);
  loop.run ();

  return 0;
}
#endif
