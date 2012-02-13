namespace Bump {
  /**
   * A Queue
   */
  public interface Queue : GLib.Object {
    /**
     * The number of items currently queued
     *
     * Please keep in mind that in multi-threaded code this value may
     * have changed by the time you see it.
     */
    public abstract int length { get; }

    /**
     * Process a single task in the queue
     *
     * This is method should not usually be called by user code (which
     * should usually be calling one of the *_execute methods
     * instead). This method assumes that any locks have already been
     * acquired.
     *
     * @param wait the maximum number of microseconds to wait for an
     *   item to appear in the queue (0 for no waiting, < 0 to wait
     *   indefinitely).
     * @return true if an item was processed, false if not
     */
    public abstract bool process (GLib.TimeSpan wait = 0);
  }
}
