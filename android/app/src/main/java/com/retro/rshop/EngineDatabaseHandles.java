package com.retro.rshop;

import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.LinkedHashSet;
import java.util.Map;
import java.util.function.Consumer;

/** Engine-local handles; native open/close boundaries finish before handoff. */
public final class EngineDatabaseHandles {
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
        boundary(done -> {
            ArrayDeque<Integer> remaining;
            synchronized (this) { remaining = new ArrayDeque<>(new ArrayList<>(handles)); handles.clear(); }
            closeNext(remaining, done);
        });
    }

    private void closeNext(ArrayDeque<Integer> remaining, Runnable done) {
        Integer id = remaining.pollFirst();
        if (id == null) { done.run(); return; }
        nativeCall.call("closeDatabase", Collections.singletonMap("id", id), new Reply() {
            public void success(Object value) { closeNext(remaining, done); }
            public void error(String code, String message, Object details) { closeNext(remaining, done); }
            public void notImplemented() { closeNext(remaining, done); }
        });
    }
}
