# Introduction #

**WARNING**: This document is nowhere near complete.

Bump is a library designed to make asynchronous and concurrent programming easier. It is written in, and designed for use in, [Vala](http://live.gnome.org/Vala), although it provides a C API and should be usable from any language which supports [GObject Introspection](http://live.gnome.org/GObjectIntrospection).

Bump's API can seem a bit strange (and perhaps a bit daunting) at first, but once you understand it it is very pleasant to work with. This guide will, I hope, help you acclimate to Bump's API so that you can work with it to develop your asynchronous and concurrent software.

This document will assume you are using Vala, though most of it should apply to any language. It also assumes a basic familiarity with GLib's [Main Event Loop](http://developer.gnome.org/glib/stable/glib-The-Main-Event-Loop.html) and [Asynchronous Methods](https://live.gnome.org/Vala/Tutorial#Asynchronous_Methods) in Vala.

# Getting Started With Tasks and Queues #

Tasks are the core of everything Bump does. Whether you want to do something synchronously, do something in an idle callback, or do something in a background thread, that _something_ is a task.

In order to run your tasks with Bump, you will generally add them to a task queue of some sort. The simplest task queue in Bump is the creatively named [Bump.TaskQueue](http://code.coeusgroup.com/bump/valadoc/Bump/Bump.TaskQueue.html). Several classes derive from `TaskQueue`, and several others are conceptually very similar but cannot derive from `TaskQueue` because they require slightly different method signatures. Knowing all this, it probably isn't too surprising that using a `TaskQueue` to execute a task will be our first example, so let's get it over with:

```
Bump.TaskQueue queue = new Bump.TaskQueue ();
queue.execute<void*> (() => {
    GLib.debug ("Hello, world!");
    return null;
  });
```

Now, nobody in their right mind would use Bump to synchronously print "Hello, world!", but Bump is capable of doing a _lot_ more, _with very little additional complexity_.

Notice that the execute method takes a type argument. That's the type of the return value. Let's take a look at the definition for the execute method, as well as the delegate type we need to pass to it:

```
public delegate G Callback<G> () throws Error;
public virtual G execute<G> (Callback<G> func, int priority = DEFAULT, Cancellable? cancellable = null) throws Error;
```

You can ignore the `priority` and `cancellable` arguments for now--we'll deal with them later. First, let's follow that type argument around... it ends up as the return type of both the callback and the `execute` method. That isn't a coincidence. The value you return from the callback gets returned by the `execute` method. For example:

```
GLib.debug (queue.execute<string> (() => {
    return "Hello, world!";
  }));
```

As you can probably guess by now, "Hello, world!" gets passed to the GLib.debug function. Just like the return value, exceptions pass right through an `execute` call:

```
try {
  queue.execute<void*> (() => {
      throw new FooError.BRAIN_FART ("I forgot what I was going to say.");
      return null;
    });
} catch (GLib.Error e) {
  GLib.error (e.message);
}
```

# Going Async #

Now that you understand how [Bump.TaskQueue.execute](http://code.coeusgroup.com/bump/valadoc/Bump/Bump.TaskQueue.execute.html) works it is time start taking a look at its siblings:
[Bump.TaskQueue.execute\_async](http://code.coeusgroup.com/bump/valadoc/Bump/Bump.TaskQueue.execute_async.html) and [Bump.TaskQueue.execute\_background](http://code.coeusgroup.com/bump/valadoc/Bump/Bump.TaskQueue.execute_background.html). The difference between the two is important: `execute_async` will run the task in an idle callback, whereas `execute_background` will run the task in a background thread. This is a recurring theme throughout Bump.

```
yield queue.execute_background<void*> (() => {
    GLib.Thread.usleep ((ulong) GLib.TimeSpan.SECOND);
    return null;
  });
```

Finally, a fleeting glimpse of usefulness! We just ran a task in a background thread, yielded control to the main loop while it ran, then resumed right where we left off. This is exactly the kind of thing you would want to do in your GUI application if you needed to perform a long-running synchronous task but didn't want to block the UI.

Of course, you're not limited to doing a single thing in the background. `Bump.TaskQueue` will spawn as many threads as it needs to take care of business, and re-use old threads when possible. It's a thread pool (like [GLib.ThreadPool](http://valadoc.org/glib-2.0/GLib.ThreadPool.html)) which plays nice with the main loop and asynchronous functions while exposing a convenient callback-based API. What's not to love?

# Placing Limits (with Semaphores) #

If you've ever done any concurrent programming before, you're probably familiar with the [mutex](http://en.wikipedia.org/wiki/Mutex). They are used to prevent multiple threads from using the same data at the same time.

Bump doesn't have a Mutex class, but it does have something better: a counting [semaphore](http://en.wikipedia.org/wiki/Semaphore_(programming)) (called [Bump.Semaphore](http://code.coeusgroup.com/bump/valadoc/bump/Bump.Semaphore.html)). Don't worry--if you set the count to 1 (the default) it will have the same behavior as a mutex.

While `Bump.Semaphore` does provide a traditional lock/unlock API, as a subclass of `Bump.TaskQueue`, it also offers our handy callback-based API:

```
Bump.Semaphore sem = new Bump.Semaphore (1);
sem.execute<void*> (() => {
    GLib.debug ("Hello, world!");
    return null;
  });
```

The synchronous `execute` call is a bit more useful here than in the basic `TaskQueue` class because it will block until the lock can be acquired.

# Priority and Cancellables #

Many, if not most, of the methods you will use with Bump take priority and [cancellable](http://valadoc.org/gio-2.0/GLib.Cancellable.html) arguments. The priority and cancellable arguments are optional, defaulting to GLib.Priority.DEFAULT and null, respectively.

Tasks given to Bump will, whenever possible, be executed first according to their priority. Potential exceptions will be clearly noted in the API reference--see [Bump.TaskQueue.execute\_async](http://code.coeusgroup.com/bump/valadoc/bump/Bump.TaskQueue.execute_async.html) for an example.

# Pools of Reusable Resources #

One of the problems with trying to do things in parallel is that sometimes you have to deal with resources which break when you try to use them concurrently. For example, if you are writing a TCP client you can't mix data from two different messages together and expect things to work.

In such a situation, you have two choices: the first option is to simply prevent the resource from being used concurrently (remember semaphores?). Sometimes this works well, but it can be a huge bottleneck. The second option is to simply open another connection. Luckily, there's a class for that: [Bump.ResourcePool](http://code.coeusgroup.com/bump/valadoc/bump/Bump.ResourcePool.html).

`ResourcePool` is designed for resources which are relatively expensive to acquire, stateful, and reusable. Examples include connections to databases (SQLite, PostgreSQL, MySQL, etc.) and network connections (HTTP, FTP, SMTP, etc.).

The easiest way to use a `Bump.ResourcePool` is to control a class which implements [GLib.Initable](http://valadoc.org/gio-2.0/GLib.Initable.html), [GLib.AsyncInitable](http://valadoc.org/gio-2.0/GLib.AsyncInitable.html), or both:

```
private Bump.ResourcePool<Foo> pool = new Bump.ResourcePool<Foo> ();

public async string do_something () {
  return yield pool.execute_background<string> ((foo_instance) => {
      return foo_instance.method_which_returns_a_string ();
    });
}
```

As you can see, you can use an `execute` method just as you would for a `Bump.TaskQueue`, but there is an extra argument to the callback. That argument is a resource instance. Once the callback completes the instance is returned to the pool, but until that happens it is yours to do with as you please.

If you prefer to avoid the callback, you can use the acquire family of methods ([acquire](http://code.coeusgroup.com/bump/valadoc/bump/Bump.ResourcePool.acquire.html), [acquire\_async](http://code.coeusgroup.com/bump/valadoc/bump/Bump.ResourcePool.acquire_async.html), and [acquire\_background](http://code.coeusgroup.com/bump/valadoc/bump/Bump.ResourcePool.acquire_background.html)) to acquire a resource and [release](http://code.coeusgroup.com/bump/valadoc/bump/Bump.ResourcePool.release.html) to release it back into the pool:

```
public async string do_something () {
  Foo foo_instance = yield pool.acquire_background ();
  string result = foo_instance.method_which_returns_a_string ();
  pool.release (foo_instance);
}
```

Of course, not everything implements `GLib.Initable` or `GLib.AsyncInitable`. If your resource is a `GLib.Object` it will be created with its default values. If your resource isn't a `GLib.Object`, or the default values are unacceptable, you can subclass `Bump.ResourcePool` and override the [Bump.Factory.create](http://code.coeusgroup.com/bump/valadoc/bump/Bump.Factory.create.html) method:

```
private class FooPool : Bump.ResourcePool<Foo> {
  public override create (int priority = DEFAULT, Cancellable? cancellable = null) throws GLib.Error {
    return new Foo (an_argument);
  }
}
```

If you are creating a `GLib.Object`, you can use the [construct\_properties](http://code.coeusgroup.com/bump/valadoc/bump/Bump.Factory.construct_properties.html) property to provide a list of construct properties which will be used when instantiating the object:

```
pool.construct_properties = {
  GLib.Parameter () { name = "prop-1", value = "foo" },
  GLib.Parameter () { name = "prop-2", value = "bar" }
};
```

It's worth noting that you can create a resource pool with a maximum number of resources by passing that number as an argument to the constructor.

# Lazy Initialization #

The [Lazy](http://code.coeusgroup.com/bump/valadoc/bump/Bump.Lazy.html) class is designed to allow lazy asynchronous initialization of a single resource, similar to a `ResourcePool` with a maximum count of one resource. However, unlike `ResourcePool`, `Lazy` does not attempt to restrict subsequent concurrent accesses--where `ResourcePool` would create another resource instance (or block until an existing one became available), `Lazy` simple returns the same resource.

Like `ResourcePool`, the easiest way to use `Lazy` is with a `GLib.Object`, preferably one which implements `GLib.Initable` and/or `GLib.AsyncInitable`, in which case you can just create and use a `Lazy` instance:

```
Bump.Lazy<Foo> lazy = new Bump.Lazy<Foo> ();

public async void do_something () throws GLib.Error {
  Foo value = yield lazy.get_value_background ();
  value.do_something_thread_safe ();
}
```

If your class is not a `GLib.Object`, you will have to override one or more member of the `create` family (The [create](http://code.coeusgroup.com/bump/valadoc/bump/Bump.Factory.create.html), [create\_async](http://code.coeusgroup.com/bump/valadoc/bump/Bump.Factory.create_async.html), and [create\_background](http://code.coeusgroup.com/bump/valadoc/bump/Bump.Factory.create_background.html)).

# Claim API #

In addition to the callback API (`execute`, `execute_async`, and `execute_background` methods), some classes in Bump provide a "Claim" API. The idea is that when you want to limit access to something, such as a resource in a `ResourcePool` or a `Semaphore`, you acquire a claim on that thing, and releasing that claim allows for it to be claimed elsewhere.

In order to reduce bugs, Bump can actually return a [Claim](http://code.coeusgroup.com/bump/valadoc/bump/Bump.Claim.html) object. In languages with automatic memory management, such as Vala, the claim will automatically be released. Exceptions, in particular, become much more feasible:

```
try {
  Bump.Claim claim = sem.claim ();
  method_which_throws_an_error ();
} catch ( GLib.Error e ) {
  Glib.error (e);
}
```

When the claim goes out of scope it is destroyed, even though you didn't explicitly free it, and a new claim can be made elsewhere.

It's worth noting that you can mix APIs at will--using the callback API will not conflict with the claim API, nor will the claim APi conflict with the callback API.