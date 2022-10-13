const std = @import("std");

const RingQueue = @import("ring_queue.zig").RingQueue;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

pub fn IdleQueue(comptime _capacity: u16) type {

    const Mutex = std.Thread.Mutex;
    const Condition = std.Thread.Condition;

    const Entry = struct {
        // zig fmt: off
        mutex     : Mutex     = .{},
        condition : Condition = .{},
        awakened  : bool      = false,
        // zig fmt: on
    };

    const EntryQueue = RingQueue(*Entry, _capacity);

    return struct {
        const Self = @This();

        pub const capacity = _capacity;

        // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

        // zig fmt: off
        _mutex   : Mutex      = .{},
        _entries : EntryQueue = .{},
        // zig fmt: on

        // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

        pub fn idle(self: *Self) void {
            var entry = Entry{};
            entry.mutex.lock();
            defer entry.mutex.unlock();

            {
                self._mutex.lock();
                defer self._mutex.unlock();
                self._entries.enqueueAssumeNotFull(&entry);
            }

            const this_thread = std.Thread.getCurrentId();
            std.debug.print("~{} idle\n", .{ this_thread });
            while (!entry.awakened) {
                entry.condition.wait(&entry.mutex);
            }
            std.debug.print("~{} wake\n", .{ this_thread });
        }

        pub fn wake(self: *Self) void {
            self._mutex.lock();
            defer self._mutex.unlock();

            while (self._entries.dequeueIfNotEmpty()) |entry| {
                entry.mutex.lock();
                defer entry.mutex.unlock();
                entry.awakened = true;
                entry.condition.signal();
            }
        }
    };
}

////////////////////////////////// T E S T S ///////////////////////////////////

test "IdleQueue basics" {
    const num_threads: u32 = 4;

    const Counter = std.atomic.Atomic(u32);

    var idle_queue = IdleQueue(num_threads){};

    var counter = Counter.init(0);

    const ThreadContext = struct {
        _idle_queue: *IdleQueue(num_threads),
        _counter: *Counter,

        fn exec(context: @This()) void {
            context._idle_queue.idle();
            _ = context._counter.fetchAdd(1, .Monotonic);
        }
    };

    var context = ThreadContext{
        ._idle_queue = &idle_queue,
        ._counter = &counter,
    };

    var threads: [num_threads]std.Thread = undefined;

    for (threads) |*thread| {
        thread.* = try std.Thread.spawn(.{}, ThreadContext.exec, .{context});
    }

    const expectEqual = std.testing.expectEqual;

    // all threads are idle, none have incremented counter
    try expectEqual(@as(u32, 0), counter.load(.Monotonic));

    std.time.sleep(std.time.ns_per_s);

    // all threads are idle, none have incremented counter
    try expectEqual(@as(u32, 0), counter.load(.Monotonic));

    idle_queue.wake();

    for (threads) |*thread| {
        thread.join();
        thread.* = undefined;
    }

    // all threads have run, all have incremented counter
    try expectEqual(num_threads, counter.load(.Monotonic));
}

//------------------------------------------------------------------------------
