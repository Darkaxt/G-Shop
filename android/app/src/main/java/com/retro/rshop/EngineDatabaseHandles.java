package com.retro.rshop;

import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.LinkedHashSet;
import java.util.Map;
import java.util.function.Consumer;
import java.util.concurrent.atomic.AtomicReference;

/** Engine-local handles; native open/close boundaries finish before handoff. */
public final class EngineDatabaseHandles {
    private static final AtomicReference<EngineDatabaseHandles> foreground = new AtomicReference<>();
    public interface Reply {
        void success(Object value);
        void error(String code, String message, Object details);
        void notImplemented();
    }
    public interface NativeCall { void call(String method, Object arguments, Reply reply); }

    // sqflite's process-wide worker pool may retire when its final handle closes.
    // Do not submit a new open into that retiring pool before close acknowledges.
    private static final ArrayDeque<Runnable> boundaries = new ArrayDeque<>();
    private static void boundary(Consumer<Runnable> operation) {
        Runnable task = () -> operation.accept(() -> {
            Runnable next;
            synchronized (boundaries) {
                boundaries.removeFirst();
                next = boundaries.peekFirst();
            }
            if (next != null) next.run();
        });
        boolean start;
        synchronized (boundaries) {
            start = boundaries.isEmpty();
            boundaries.addLast(task);
        }
        if (start) task.run();
    }

    private final NativeCall nativeCall;
    private final LinkedHashSet<Integer> handles = new LinkedHashSet<>();
    private boolean closed;
    public EngineDatabaseHandles(NativeCall nativeCall) { this.nativeCall = nativeCall; }

    /** Called on Activity setup, before its Dart entrypoint can open databases.
     * Android may not destroy the previous Activity until after the new one resumes. */
    public void claimForeground() {
        EngineDatabaseHandles previous = foreground.getAndSet(this);
        if (previous != null && previous != this) previous.close();
    }

    private static Reply completed(Reply reply, Runnable done, Consumer<Object> success) {
        return new Reply() {
            public void success(Object value) {
                try { success.accept(value); reply.success(value); } finally { done.run(); }
            }
            public void error(String code, String message, Object details) {
                try { reply.error(code, message, details); } finally { done.run(); }
            }
            public void notImplemented() {
                try { reply.notImplemented(); } finally { done.run(); }
            }
        };
    }

    public void call(String method, Object arguments, Reply reply) {
        synchronized (this) {
            if (closed) { reply.error("database_engine_closed", "Database owner closed", null); return; }
        }
        if (method.equals("openDatabase")) {
            Map<Object, Object> options = new HashMap<>((Map<?, ?>) arguments);
            // Dart's factory still reuses a connection inside one isolate. Never
            // reuse a native handle across engines with independent transactions.
            options.put("singleInstance", false);
            boundary(done -> {
                synchronized (this) {
                    if (closed) {
                        reply.error("database_engine_closed", "Database owner closed", null);
                        done.run(); return;
                    }
                    nativeCall.call(method, options, completed(reply, done, value -> {
                        int id = value instanceof Number ? ((Number) value).intValue()
                                : ((Number) ((Map<?, ?>) value).get("id")).intValue();
                        synchronized (this) { handles.add(id); }
                    }));
                }
            });
        } else if (method.equals("closeDatabase")) {
            int id = ((Number) ((Map<?, ?>) arguments).get("id")).intValue();
            boundary(done -> nativeCall.call(method, arguments,
                    completed(reply, done, value -> { synchronized (this) { handles.remove(id); } })));
        } else {
            synchronized (this) {
                if (closed) reply.error("database_engine_closed", "Database owner closed", null);
                else nativeCall.call(method, arguments, reply);
            }
        }
    }

    public void close() {
        synchronized (this) {
            if (closed) return;
            closed = true;
        }
        foreground.compareAndSet(this, null);
        boundary(done -> {
            ArrayDeque<Integer> remaining;
            synchronized (this) { remaining = new ArrayDeque<>(new ArrayList<>(handles)); handles.clear(); }
            closeNext(remaining, done);
        });
    }

    private void closeNext(ArrayDeque<Integer> remaining, Runnable done) {
        Integer id = remaining.pollFirst();
        if (id == null) { done.run(); return; }
        Reply closed = new Reply() {
            public void success(Object value) { closeNext(remaining, done); }
            public void error(String code, String message, Object details) { closeNext(remaining, done); }
            public void notImplemented() { closeNext(remaining, done); }
        };
        Map<String, Object> rollback = new HashMap<>();
        rollback.put("id", id);
        rollback.put("sql", "ROLLBACK");
        rollback.put("transactionId", -1); // sqflite's forced transaction boundary
        rollback.put("inTransaction", false);
        // Android's pool close does not release an acquired transaction. End
        // ours on its SQL worker first. An idle handle reports no active txn;
        // either way, enqueue close before sqflite resumes its abandoned queue.
        nativeCall.call("execute", rollback, new Reply() {
            private void closeHandle() { nativeCall.call("closeDatabase", Collections.singletonMap("id", id), closed); }
            public void success(Object value) { closeHandle(); }
            public void error(String code, String message, Object details) { closeHandle(); }
            public void notImplemented() { closeHandle(); }
        });
    }
}
