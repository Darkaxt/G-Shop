package com.retro.rshop;

import org.junit.Test;
import static org.junit.Assert.*;
import java.util.*;

public class EngineDatabaseHandlesTest {
    private static class Reply implements EngineDatabaseHandles.Reply {
        Object value;
        String error;
        public void success(Object value) { this.value = value; }
        public void error(String code, String message, Object details) { error = code; }
        public void notImplemented() { error = "notImplemented"; }
    }
    private static class Native implements EngineDatabaseHandles.NativeCall {
        final List<String> events = new ArrayList<>();
        final Deque<EngineDatabaseHandles.Reply> closes = new ArrayDeque<>();
        EngineDatabaseHandles.Reply opening;
        boolean holdOpen;
        int next = 1;
        public void call(String method, Object args, EngineDatabaseHandles.Reply reply) {
            if (method.equals("openDatabase")) {
                assertEquals(false, ((Map<?, ?>) args).get("singleInstance"));
                events.add("open");
                if (holdOpen) opening = reply;
                else reply.success(Collections.singletonMap("id", next++));
            } else if (method.equals("closeDatabase")) {
                events.add("close:" + ((Map<?, ?>) args).get("id"));
                closes.add(reply);
            } else { events.add(method); reply.success(null); }
        }
        void finishClose() { closes.removeFirst().success(null); }
    }
    private static final Map<String, Object> OPEN = Collections.singletonMap("path", "/fixture.db");

    @Test public void newEngineWaitsForActualOldHandleClosureAndRejectsOldQueuedSql() {
        Native backend = new Native();
        EngineDatabaseHandles old = new EngineDatabaseHandles(backend);
        old.call("openDatabase", OPEN, new Reply());
        old.call("execute", Collections.singletonMap("sql", "BEGIN"), new Reply());
        old.close();
        Reply rejected = new Reply();
        old.call("execute", Collections.singletonMap("sql", "INSERT"), rejected);
        assertEquals("database_engine_closed", rejected.error);
        EngineDatabaseHandles next = new EngineDatabaseHandles(backend);
        Reply opened = new Reply();
        next.call("openDatabase", OPEN, opened);
        assertEquals(Arrays.asList("open", "execute", "close:1"), backend.events);
        assertNull(opened.value);
        backend.finishClose();
        assertNotNull(opened.value);
        assertEquals(Arrays.asList("open", "execute", "close:1", "open"), backend.events);
        next.close(); backend.finishClose();
    }

    @Test public void openingThatCompletesAfterDetachIsClosedBeforeTheNextEngineOpens() {
        Native backend = new Native(); backend.holdOpen = true;
        EngineDatabaseHandles old = new EngineDatabaseHandles(backend);
        old.call("openDatabase", OPEN, new Reply());
        old.close();
        EngineDatabaseHandles next = new EngineDatabaseHandles(backend);
        next.call("openDatabase", OPEN, new Reply());
        assertEquals(Collections.singletonList("open"), backend.events);
        backend.holdOpen = false;
        backend.opening.success(Collections.singletonMap("id", backend.next++));
        assertEquals(Arrays.asList("open", "close:1"), backend.events);
        backend.finishClose();
        assertEquals(Arrays.asList("open", "close:1", "open"), backend.events);
        next.close(); backend.finishClose();
    }

    @Test public void explicitCloseIsNotRepeatedAndOtherEngineHandlesRemainOwned() {
        Native backend = new Native();
        EngineDatabaseHandles a = new EngineDatabaseHandles(backend);
        EngineDatabaseHandles b = new EngineDatabaseHandles(backend);
        a.call("openDatabase", OPEN, new Reply());
        b.call("openDatabase", OPEN, new Reply());
        a.call("closeDatabase", Collections.singletonMap("id", 1), new Reply());
        backend.finishClose();
        a.close(); a.close();
        assertEquals(Arrays.asList("open", "open", "close:1"), backend.events);
        b.close();
        assertEquals("close:2", backend.events.get(3));
        backend.finishClose();
    }
}
