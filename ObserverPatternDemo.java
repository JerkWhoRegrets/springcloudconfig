import java.io.*;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicInteger;

/**
 * ObserverPatternDemo.java
 *
 * A single-file, in-depth demonstration of the Observer pattern.
 * - Subject / Observable (EventBus)
 * - Observers with filters and priorities
 * - Synchronous and asynchronous dispatch
 * - Durable (sticky) subscriptions
 * - Fault tolerant dispatch (observer exceptions are isolated)
 * - Example observers: Logger, Alert, Stats, Unreliable
 *
 * Run main() to see a demonstration.
 */
public class ObserverPatternDemo {

    // -------------------------
    // Domain: Events & Types
    // -------------------------
    public enum EventType {
        TEMPERATURE_READING,
        HUMIDITY_READING,
        MOTION_DETECTED,
        SYSTEM_ALERT,
        HEARTBEAT
    }

    public static class Event {
        public final EventType type;
        public final String source;
        public final double value;
        public final LocalDateTime timestamp;

        public Event(EventType type, String source, double value) {
            this.type = type;
            this.source = source;
            this.value = value;
            this.timestamp = LocalDateTime.now();
        }

        @Override
        public String toString() {
            return String.format("[%s] %s from %s = %.2f",
                    timestamp.format(DateTimeFormatter.ISO_LOCAL_TIME), type, source, value);
        }
    }

    // -------------------------
    // Observer interface
    // -------------------------
    public interface Observer {
        /**
         * Called when an event is delivered.
         *
         * @param e event
         * @throws Exception observers may throw, but subject will isolate exceptions
         */
        void onEvent(Event e) throws Exception;

        /**
         * Human friendly name for this observer.
         */
        String name();
    }

    // -------------------------
    // Subscription descriptor
    // -------------------------
    public static class Subscription {
        public final Observer observer;
        public final Set<EventType> filter; // null or empty -> all events
        public final int priority; // higher priority observers get notified earlier
        public final boolean async; // whether notifications should be async
        public final boolean durable; // whether observer gets last event immediately on subscribe

        public Subscription(Observer observer, Set<EventType> filter, int priority, boolean async, boolean durable) {
            this.observer = observer;
            this.filter = (filter == null || filter.isEmpty()) ? null : EnumSet.copyOf(filter);
            this.priority = priority;
            this.async = async;
            this.durable = durable;
        }

        public boolean matches(Event e) {
            return filter == null || filter.contains(e.type);
        }
    }

    // -------------------------
    // Subject / EventBus
    // -------------------------
    public static class EventBus {
        private final List<Subscription> subscribers = new CopyOnWriteArrayList<>();
        private final ExecutorService asyncExecutor;
        private final boolean allowSync; // if false, everything is async
        private final Map<EventType, Event> lastEventByType = new ConcurrentHashMap<>();

        public EventBus(int asyncThreads, boolean allowSync) {
            this.asyncExecutor = Executors.newFixedThreadPool(Math.max(1, asyncThreads));
            this.allowSync = allowSync;
        }

        /**
         * Subscribe with options.
         */
        public void subscribe(Subscription sub) {
            subscribers.add(sub);
            // sort by priority descending for delivery order (higher priority first)
            subscribers.sort(Comparator.comparingInt((Subscription s) -> s.priority).reversed());
            // deliver last event immediately if durable
            if (sub.durable) {
                // deliver most recent event(s) that match the subscription
                for (Event e : lastEventByType.values()) {
                    if (sub.matches(e)) {
                        deliverToSubscriber(sub, e);
                    }
                }
            }
        }

        public void unsubscribe(Observer o) {
            subscribers.removeIf(s -> s.observer.equals(o));
        }

        /**
         * Publish an event. Will capture it as "last" for durable subscribers.
         */
        public void publish(Event e) {
            // record last event by type
            lastEventByType.put(e.type, e);

            // snapshot current subscribers
            for (Subscription s : subscribers) {
                if (!s.matches(e)) continue;
                // if async or global async-only mode, dispatch asynchronously
                if (s.async || !allowSync) {
                    asyncExecutor.submit(() -> safeNotify(s.observer, e));
                } else {
                    // synchronous delivery in calling thread
                    safeNotify(s.observer, e);
                }
            }
        }

        private void deliverToSubscriber(Subscription s, Event e) {
            if (s.async || !allowSync) {
                asyncExecutor.submit(() -> safeNotify(s.observer, e));
            } else {
                safeNotify(s.observer, e);
            }
        }

        // safety wrapper to isolate observer exceptions
        private void safeNotify(Observer o, Event e) {
            try {
                o.onEvent(e);
            } catch (Exception ex) {
                System.err.printf("Observer %s threw exception handling event %s: %s%n",
                        o.name(), e, ex.toString());
            }
        }

        public void shutdown() {
            asyncExecutor.shutdown();
            try {
                if (!asyncExecutor.awaitTermination(3, TimeUnit.SECONDS)) {
                    asyncExecutor.shutdownNow();
                }
            } catch (InterruptedException ie) {
                asyncExecutor.shutdownNow();
                Thread.currentThread().interrupt();
            }
        }
    }

    // -------------------------
    // Concrete Observers
    // -------------------------

    /**
     * FileLoggerObserver writes every event it receives to a file.
     */
    public static class FileLoggerObserver implements Observer, Closeable {
        private final String filename;
        private final BufferedWriter writer;
        private final String name;

        public FileLoggerObserver(String name, String filename) throws IOException {
            this.name = name;
            this.filename = filename;
            this.writer = new BufferedWriter(new FileWriter(filename, true));
        }

        @Override
        public void onEvent(Event e) throws Exception {
            synchronized (writer) {
                writer.write(LocalDateTime.now().format(DateTimeFormatter.ISO_LOCAL_DATE_TIME) +
                        " - " + e.toString() + "\n");
                writer.flush();
            }
        }

        @Override
        public String name() { return name; }

        @Override
        public void close() throws IOException {
            writer.close();
        }
    }

    /**
     * AlertObserver simulates sending alerts (prints to console).
     * It will only listen for SYSTEM_ALERT and threshold breaches.
     */
    public static class AlertObserver implements Observer {
        private final String name;

        public AlertObserver(String name) { this.name = name; }

        @Override
        public void onEvent(Event e) {
            // simulate alert channel
            System.out.println("!!! ALERT [" + name + "]: " + e.toString());
        }

        @Override
        public String name() { return name; }
    }

    /**
     * StatsObserver aggregates counts per EventType and prints summary occasionally.
     */
    public static class StatsObserver implements Observer {
        private final String name;
        private final Map<EventType, AtomicInteger> counters = new ConcurrentHashMap<>();
        private final ScheduledExecutorService printer = Executors.newSingleThreadScheduledExecutor();

        public StatsObserver(String name) {
            this.name = name;
            for (EventType t : EventType.values()) counters.put(t, new AtomicInteger(0));
            // periodic print
            printer.scheduleAtFixedRate(this::printStats, 5, 5, TimeUnit.SECONDS);
        }

        @Override
        public void onEvent(Event e) {
            counters.get(e.type).incrementAndGet();
        }

        @Override
        public String name() { return name; }

        public void printStats() {
            StringBuilder sb = new StringBuilder();
            sb.append("StatsObserver[").append(name).append("] summary: ");
            for (EventType t : EventType.values()) {
                sb.append(t).append("=")
                        .append(counters.get(t).get()).append(" ");
            }
            System.out.println(sb.toString());
        }

        public void shutdown() {
            printer.shutdownNow();
        }
    }

    /**
     * UnreliableObserver simulates an observer that fails intermittently.
     * It is useful to demonstrate that one observer's exception doesn't stop others.
     */
    public static class UnreliableObserver implements Observer {
        private final String name;
        private final Random rnd = new Random();

        public UnreliableObserver(String name) { this.name = name; }

        @Override
        public void onEvent(Event e) throws Exception {
            if (rnd.nextDouble() < 0.25) {
                throw new RuntimeException("simulated random failure");
            }
            System.out.println("UnreliableObserver[" + name + "] processed: " + e);
        }

        @Override
        public String name() { return name; }
    }

    // -------------------------
    // Demo & Tests
    // -------------------------
    public static void main(String[] args) throws Exception {
        System.out.println("=== Observer Pattern Demo (single-file, in-depth) ===");

        // Create event bus with 4 async threads and allow synchronous dispatch for some subscribers
        EventBus bus = new EventBus(4, true);

        // Create observers
        FileLoggerObserver fileLogger = new FileLoggerObserver("FileLogger", "events.log");
        AlertObserver alertObs = new AlertObserver("OpsTeam");
        StatsObserver statsObs = new StatsObserver("GlobalStats");
        UnreliableObserver unreliable = new UnreliableObserver("FlakyOne");

        // Subscribe: FileLogger receives all events, async=false (sync delivery), durable=true (get last)
        bus.subscribe(new Subscription(fileLogger, null, 50, false, true));

        // Stats: receives all events, async=true, lower priority
        bus.subscribe(new Subscription(statsObs, null, 10, true, false));

        // Alert: only system alerts and temperature above threshold — filter by type for now
        bus.subscribe(new Subscription(alertObs, EnumSet.of(EventType.SYSTEM_ALERT), 80, true, false));

        // Flaky observer that listens to motion events asynchronously
        bus.subscribe(new Subscription(unreliable, EnumSet.of(EventType.MOTION_DETECTED), 20, true, false));

        // Publish a "sticky" heartbeat event (durable) so that later durable subs get it immediately
        Event heartbeat = new Event(EventType.HEARTBEAT, "system", 1.0);
        bus.publish(heartbeat);

        // Simulate producers publishing events concurrently
        ExecutorService producers = Executors.newFixedThreadPool(3);
        Runnable tempProducer = () -> {
            Random rnd = new Random();
            for (int i = 0; i < 20; i++) {
                double v = 20 + rnd.nextGaussian() * 5;
                Event e = new Event(EventType.TEMPERATURE_READING, "sensor-T" + ThreadLocalRandom.current().nextInt(3), v);
                bus.publish(e);
                sleepMillis(100 + rnd.nextInt(200));
            }
        };
        Runnable motionProducer = () -> {
            Random rnd = new Random();
            for (int i = 0; i < 12; i++) {
                double v = rnd.nextDouble() < 0.12 ? 1.0 : 0.0;
                Event e = new Event(EventType.MOTION_DETECTED, "sensor-M" + ThreadLocalRandom.current().nextInt(2), v);
                bus.publish(e);
                sleepMillis(150 + rnd.nextInt(300));
            }
        };
        Runnable sysProducer = () -> {
            // occasionally publish system alert
            try {
                sleepMillis(500);
                bus.publish(new Event(EventType.SYSTEM_ALERT, "sys", 0.0));
            } catch (Exception ignored) {}
        };

        producers.submit(tempProducer);
        producers.submit(motionProducer);
        producers.submit(sysProducer);

        // After some time, subscribe a new durable observer and show it gets the last heartbeat immediately
        Thread.sleep(700);
        System.out.println("\n--- Subscribing a late durable FileLogger2 (should receive last heartbeat immediately) ---");
        FileLoggerObserver fileLogger2 = new FileLoggerObserver("FileLogger2", "events2.log");
        bus.subscribe(new Subscription(fileLogger2, null, 40, false, true));

        // Let producers run
        producers.shutdown();
        producers.awaitTermination(5, TimeUnit.SECONDS);

        // Simulate a high-temp event to trigger an alert — demonstrate dynamic subscription with filter by threshold
        Event highTemp = new Event(EventType.TEMPERATURE_READING, "sensor-T-99", 55.4);
        System.out.println("\nPublishing a high temperature event to trigger manual alert logic...");
        bus.publish(highTemp);

        // Demonstrate runtime unsubscribe
        System.out.println("\nUnsubscribing FlakyOne (unreliable) observer...");
        bus.unsubscribe(unreliable);

        // Publish some more motion to show FlakyOne no longer receives it
        bus.publish(new Event(EventType.MOTION_DETECTED, "sensor-MX", 1.0));

        // Manually check stats and then shutdown
        Thread.sleep(1500);
        System.out.println("\nFinal stats snapshot:");
        statsObs.printStats();

        // Cleanup
        System.out.println("\nShutting down event bus and observers...");
        fileLogger.close();
        fileLogger2.close();
        statsObs.shutdown();
        bus.shutdown();

        System.out.println("Demo complete. Check 'events.log' and 'events2.log' files for persisted records.");
    }

    private static void sleepMillis(int ms) {
        try { Thread.sleep(ms); } catch (InterruptedException e) { Thread.currentThread().interrupt(); }
    }
}