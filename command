import java.io.*;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;

/**
 * SmartHomeCommandStandard.java
 *
 * Single-file demonstration of the Command Pattern (Standard level).
 *
 * Devices:
 *  - Light (on/off, brightness)
 *  - Thermostat / AC (set temperature, off)
 *  - Door (lock/unlock)
 *
 * Pattern elements:
 *  - Command interface (execute + undo)
 *  - Concrete commands for each device action
 *  - RemoteControl invoker with slots & undo stack
 *  - Simple Logger for history
 *
 * Interactive console UI is provided at the bottom of this file.
 *
 * This file intentionally contains additional comments, helper code, and
 * user interface logic to reach ~300+ lines while remaining focused and educational.
 */

public class SmartHomeCommandStandard {

    // ---------------------------
    // Command pattern: interface
    // ---------------------------
    public interface Command {
        void execute();
        void undo();
        String name();
    }

    // ---------------------------
    // Logger (simple, thread-safe)
    // ---------------------------
    public static class Logger {
        private final BufferedWriter writer;
        private final List<String> history = Collections.synchronizedList(new ArrayList<>());
        private final DateTimeFormatter fmt = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");

        public Logger(String filename) throws IOException {
            this.writer = new BufferedWriter(new FileWriter(filename, true));
        }

        public synchronized void log(String msg) {
            String ts = LocalDateTime.now().format(fmt);
            String line = ts + " - " + msg;
            history.add(line);
            try {
                writer.write(line);
                writer.newLine();
                writer.flush();
            } catch (IOException e) {
                System.out.println("Logger error: " + e.getMessage());
            }
        }

        public List<String> recent(int n) {
            synchronized (history) {
                int from = Math.max(0, history.size() - n);
                return new ArrayList<>(history.subList(from, history.size()));
            }
        }

        public void close() {
            try {
                writer.close();
            } catch (IOException ignored) {}
        }
    }

    // ---------------------------
    // Receivers (Devices)
    // ---------------------------

    // Light with brightness support (0-100)
    public static class Light {
        private final String name;
        private boolean on = false;
        private int brightness = 100; // default 100

        public Light(String name) {
            this.name = name;
        }

        public void on() {
            on = true;
            System.out.println("Light [" + name + "] turned ON (brightness=" + brightness + "%)");
        }

        public void off() {
            on = false;
            System.out.println("Light [" + name + "] turned OFF");
        }

        public void setBrightness(int value) {
            brightness = Math.max(0, Math.min(100, value));
            System.out.println("Light [" + name + "] brightness set to " + brightness + "%");
        }

        public boolean isOn() { return on; }
        public int getBrightness() { return brightness; }
        public String getName() { return name; }
    }

    // Thermostat / AC device
    public static class Thermostat {
        private final String name;
        private boolean on = false;
        private double temperature = 22.0; // Celsius

        public Thermostat(String name) {
            this.name = name;
        }

        public void setTemperature(double temp) {
            temperature = temp;
            on = true;
            System.out.println("Thermostat [" + name + "] set to " + String.format("%.1f", temperature) + "°C");
        }

        public void off() {
            on = false;
            System.out.println("Thermostat [" + name + "] turned OFF");
        }

        public boolean isOn() { return on; }
        public double getTemperature() { return temperature; }
        public String getName() { return name; }
    }

    // Door with lock/unlock semantics
    public static class Door {
        private final String name;
        private boolean locked = false;

        public Door(String name) {
            this.name = name;
        }

        public void lock() {
            locked = true;
            System.out.println("Door [" + name + "] LOCKED");
        }

        public void unlock() {
            locked = false;
            System.out.println("Door [" + name + "] UNLOCKED");
        }

        public boolean isLocked() { return locked; }
        public String getName() { return name; }
    }

    // ---------------------------
    // Concrete Commands
    // ---------------------------

    // Light ON command
    public static class LightOnCommand implements Command {
        private final Light light;
        private final Logger logger;
        private boolean prevState;
        private int prevBrightness;

        public LightOnCommand(Light light, Logger logger) {
            this.light = light;
            this.logger = logger;
        }

        @Override
        public void execute() {
            prevState = light.isOn();
            prevBrightness = light.getBrightness();
            light.on();
            logger.log("Executed: " + name());
        }

        @Override
        public void undo() {
            if (!prevState) {
                light.off();
            } else {
                light.setBrightness(prevBrightness);
                light.on();
            }
            logger.log("Undo: " + name());
        }

        @Override
        public String name() {
            return "LightOn(" + light.getName() + ")";
        }
    }

    // Light OFF command
    public static class LightOffCommand implements Command {
        private final Light light;
        private final Logger logger;
        private boolean prevState;
        private int prevBrightness;

        public LightOffCommand(Light light, Logger logger) {
            this.light = light;
            this.logger = logger;
        }

        @Override
        public void execute() {
            prevState = light.isOn();
            prevBrightness = light.getBrightness();
            light.off();
            logger.log("Executed: " + name());
        }

        @Override
        public void undo() {
            if (prevState) {
                light.setBrightness(prevBrightness);
                light.on();
            } else {
                light.off();
            }
            logger.log("Undo: " + name());
        }

        @Override
        public String name() {
            return "LightOff(" + light.getName() + ")";
        }
    }

    // Light Dim command (set brightness)
    public static class LightDimCommand implements Command {
        private final Light light;
        private final int level;
        private final Logger logger;
        private int prevBrightness;
        private boolean prevState;

        public LightDimCommand(Light light, int level, Logger logger) {
            this.light = light;
            this.level = Math.max(0, Math.min(100, level));
            this.logger = logger;
        }

        @Override
        public void execute() {
            prevBrightness = light.getBrightness();
            prevState = light.isOn();
            light.setBrightness(level);
            light.on();
            logger.log("Executed: " + name());
        }

        @Override
        public void undo() {
            light.setBrightness(prevBrightness);
            if (!prevState) light.off();
            logger.log("Undo: " + name());
        }

        @Override
        public String name() {
            return "LightDim(" + light.getName() + "," + level + ")";
        }
    }

    // Thermostat set temperature
    public static class ThermostatSetCommand implements Command {
        private final Thermostat thermostat;
        private final double target;
        private final Logger logger;
        private double prevTemp;
        private boolean prevState;

        public ThermostatSetCommand(Thermostat thermostat, double target, Logger logger) {
            this.thermostat = thermostat;
            this.target = target;
            this.logger = logger;
        }

        @Override
        public void execute() {
            prevTemp = thermostat.getTemperature();
            prevState = thermostat.isOn();
            thermostat.setTemperature(target);
            logger.log("Executed: " + name());
        }

        @Override
        public void undo() {
            if (!prevState) thermostat.off();
            thermostat.setTemperature(prevTemp);
            logger.log("Undo: " + name());
        }

        @Override
        public String name() {
            return "ThermostatSet(" + thermostat.getName() + "," + String.format("%.1f", target) + ")";
        }
    }

    // Thermostat OFF
    public static class ThermostatOffCommand implements Command {
        private final Thermostat thermostat;
        private final Logger logger;
        private double prevTemp;
        private boolean prevState;

        public ThermostatOffCommand(Thermostat thermostat, Logger logger) {
            this.thermostat = thermostat;
            this.logger = logger;
        }

        @Override
        public void execute() {
            prevTemp = thermostat.getTemperature();
            prevState = thermostat.isOn();
            thermostat.off();
            logger.log("Executed: " + name());
        }

        @Override
        public void undo() {
            if (prevState) thermostat.setTemperature(prevTemp);
            logger.log("Undo: " + name());
        }

        @Override
        public String name() {
            return "ThermostatOff(" + thermostat.getName() + ")";
        }
    }

    // Door Lock command
    public static class DoorLockCommand implements Command {
        private final Door door;
        private final Logger logger;
        private boolean prevLocked;

        public DoorLockCommand(Door door, Logger logger) {
            this.door = door;
            this.logger = logger;
        }

        @Override
        public void execute() {
            prevLocked = door.isLocked();
            door.lock();
            logger.log("Executed: " + name());
        }

        @Override
        public void undo() {
            if (!prevLocked) door.unlock();
            logger.log("Undo: " + name());
        }

        @Override
        public String name() {
            return "DoorLock(" + door.getName() + ")";
        }
    }

    // Door Unlock command
    public static class DoorUnlockCommand implements Command {
        private final Door door;
        private final Logger logger;
        private boolean prevLocked;

        public DoorUnlockCommand(Door door, Logger logger) {
            this.door = door;
            this.logger = logger;
        }

        @Override
        public void execute() {
            prevLocked = door.isLocked();
            door.unlock();
            logger.log("Executed: " + name());
        }

        @Override
        public void undo() {
            if (prevLocked) door.lock();
            logger.log("Undo: " + name());
        }

        @Override
        public String name() {
            return "DoorUnlock(" + door.getName() + ")";
        }
    }

    // ---------------------------
    // Macro command (optional small convenience)
    // ---------------------------
    public static class MacroCommand implements Command {
        private final String label;
        private final List<Command> commands = new ArrayList<>();
        private final Logger logger;

        public MacroCommand(String label, Logger logger) {
            this.label = label;
            this.logger = logger;
        }

        public void add(Command c) { commands.add(c); }

        @Override
        public void execute() {
            logger.log("Executing macro: " + name());
            for (Command c : commands) c.execute();
            logger.log("Macro executed: " + name());
        }

        @Override
        public void undo() {
            logger.log("Undoing macro: " + name());
            ListIterator<Command> it = commands.listIterator(commands.size());
            while (it.hasPrevious()) {
                Command c = it.previous();
                c.undo();
            }
            logger.log("Macro undone: " + name());
        }

        @Override
        public String name() {
            return "Macro(" + label + ")";
        }
    }

    // ---------------------------
    // RemoteControl (Invoker)
    // ---------------------------
    public static class RemoteControl {
        private final Map<Integer, Command> slots = new HashMap<>();
        private final Deque<Command> undoStack = new ArrayDeque<>();
        private final Logger logger;
        private final int maxSlots;

        public RemoteControl(int maxSlots, Logger logger) {
            this.maxSlots = Math.max(4, maxSlots);
            this.logger = logger;
        }

        public void setSlot(int slot, Command command) {
            if (slot < 0 || slot >= maxSlots) {
                System.out.println("Invalid slot. Valid 0.." + (maxSlots - 1));
                return;
            }
            slots.put(slot, command);
            logger.log("Assigned slot " + slot + " -> " + (command == null ? "null" : command.name()));
        }

        public void press(int slot) {
            Command c = slots.get(slot);
            if (c == null) {
                System.out.println("Slot " + slot + " is empty.");
                return;
            }
            c.execute();
            undoStack.push(c);
            logger.log("Pressed slot " + slot + " -> " + c.name());
        }

        public void undo() {
            if (undoStack.isEmpty()) {
                System.out.println("Nothing to undo.");
                return;
            }
            Command c = undoStack.pop();
            c.undo();
            logger.log("Undo invoked for " + c.name());
        }

        public void clearSlot(int slot) {
            slots.remove(slot);
            logger.log("Cleared slot " + slot);
        }

        public void listSlots() {
            System.out.println("\nRemote slots:");
            for (int i = 0; i < maxSlots; i++) {
                Command c = slots.get(i);
                System.out.printf("%2d : %s%n", i, (c == null ? "[empty]" : c.name()));
            }
        }
    }

    // ---------------------------
    // Console UI & application wiring
    // ---------------------------
    public static class ConsoleApp {
        private final Scanner sc = new Scanner(System.in);
        private final Logger logger;
        private final RemoteControl remote;
        private final Map<String, Light> lights = new LinkedHashMap<>();
        private final Map<String, Thermostat> thermostats = new LinkedHashMap<>();
        private final Map<String, Door> doors = new LinkedHashMap<>();

        public ConsoleApp(Logger logger) {
            this.logger = logger;
            this.remote = new RemoteControl(8, logger);
            seedDevices();
            seedDefaultRemoteAssignments();
        }

        private void seedDevices() {
            // sample devices
            lights.put("Living", new Light("Living"));
            lights.put("Kitchen", new Light("Kitchen"));
            lights.put("Bedroom", new Light("Bedroom"));

            thermostats.put("Hall", new Thermostat("Hall"));
            // add more if desired

            doors.put("Front", new Door("Front"));
            doors.put("Back", new Door("Back"));
        }

        private void seedDefaultRemoteAssignments() {
            // assign a few default commands to slots for convenience
            remote.setSlot(0, new LightOnCommand(lights.get("Living"), logger));
            remote.setSlot(1, new LightOffCommand(lights.get("Living"), logger));
            remote.setSlot(2, new ThermostatSetCommand(thermostats.get("Hall"), 21.5, logger));
            remote.setSlot(3, new DoorLockCommand(doors.get("Front"), logger));
        }

        public void run() {
            System.out.println("=== Smart Home Control (Command Pattern - Standard) ===");
            boolean running = true;
            while (running) {
                printMainMenu();
                String input = sc.nextLine().trim();
                switch (input) {
                    case "1" -> deviceMenu();
                    case "2" -> remoteMenu();
                    case "3" -> scheduleMacroMenu();
                    case "4" -> viewHistoryMenu();
                    case "5" -> remote.listSlots();
                    case "6" -> remote.undo();
                    case "0" -> {
                        System.out.println("Exiting application...");
                        running = false;
                    }
                    default -> System.out.println("Unknown option.");
                }
            }
            shutdown();
        }

        private void printMainMenu() {
            System.out.println("\nMain Menu:");
            System.out.println("1. Device control (create commands & execute)");
            System.out.println("2. Configure remote slots (assign commands to slots)");
            System.out.println("3. Create & run a simple macro (scene)");
            System.out.println("4. View log/history");
            System.out.println("5. Show remote slot assignments");
            System.out.println("6. Undo last remote action");
            System.out.println("0. Exit");
            System.out.print("Choice: ");
        }

        // Device menu allows creating commands on the fly and executing them
        private void deviceMenu() {
            System.out.println("\nDevice Types:");
            System.out.println("1. Lights");
            System.out.println("2. Thermostat");
            System.out.println("3. Doors");
            System.out.println("0. Back");
            System.out.print("Choose: ");
            String t = sc.nextLine().trim();
            switch (t) {
                case "1" -> lightsControl();
                case "2" -> thermostatControl();
                case "3" -> doorsControl();
                case "0" -> {}
                default -> System.out.println("Invalid selection.");
            }
        }

        private void lightsControl() {
            System.out.println("\nLights:");
            listKeys(lights.keySet());
            System.out.print("Enter light name (or 'back'): ");
            String name = sc.nextLine().trim();
            if (name.equalsIgnoreCase("back")) return;
            Light light = lights.get(name);
            if (light == null) { System.out.println("No such light."); return; }

            System.out.println("Actions: 1) On  2) Off  3) Dim");
            System.out.print("Choose: ");
            String a = sc.nextLine().trim();
            Command cmd = null;
            switch (a) {
                case "1": cmd = new LightOnCommand(light, logger); break;
                case "2": cmd = new LightOffCommand(light, logger); break;
                case "3":
                    System.out.print("Enter brightness 0-100: ");
                    int b = parseIntOrDefault(sc.nextLine().trim(), light.getBrightness());
                    cmd = new LightDimCommand(light, b, logger);
                    break;
                default: System.out.println("Invalid action."); return;
            }
            cmd.execute();
        }

        private void thermostatControl() {
            System.out.println("\nThermostats:");
            listKeys(thermostats.keySet());
            System.out.print("Enter thermostat name (or 'back'): ");
            String name = sc.nextLine().trim();
            if (name.equalsIgnoreCase("back")) return;
            Thermostat t = thermostats.get(name);
            if (t == null) { System.out.println("No such thermostat."); return; }

            System.out.println("Actions: 1) Set Temp  2) Off");
            System.out.print("Choose: ");
            String a = sc.nextLine().trim();
            Command cmd = null;
            switch (a) {
                case "1":
                    System.out.print("Enter temperature (°C): ");
                    double temp = parseDoubleOrDefault(sc.nextLine().trim(), t.getTemperature());
                    cmd = new ThermostatSetCommand(t, temp, logger);
                    break;
                case "2":
                    cmd = new ThermostatOffCommand(t, logger);
                    break;
                default: System.out.println("Invalid action."); return;
            }
            cmd.execute();
        }

        private void doorsControl() {
            System.out.println("\nDoors:");
            listKeys(doors.keySet());
            System.out.print("Enter door name (or 'back'): ");
            String name = sc.nextLine().trim();
            if (name.equalsIgnoreCase("back")) return;
            Door d = doors.get(name);
            if (d == null) { System.out.println("No such door."); return; }

            System.out.println("Actions: 1) Lock  2) Unlock");
            System.out.print("Choose: ");
            String a = sc.nextLine().trim();
            Command cmd = null;
            switch (a) {
                case "1": cmd = new DoorLockCommand(d, logger); break;
                case "2": cmd = new DoorUnlockCommand(d, logger); break;
                default: System.out.println("Invalid action."); return;
            }
            cmd.execute();
        }

        // Remote configuration menu
        private void remoteMenu() {
            System.out.println("\nRemote Configuration:");
            remote.listSlots();
            System.out.print("Enter slot number to assign (or 'back'): ");
            String s = sc.nextLine().trim();
            if (s.equalsIgnoreCase("back")) return;
            int slot = parseIntOrDefault(s, -1);
            if (slot < 0) { System.out.println("Invalid slot."); return; }

            System.out.println("Assign command type:");
            System.out.println("1. Light On");
            System.out.println("2. Light Off");
            System.out.println("3. Light Dim");
            System.out.println("4. Thermostat Set");
            System.out.println("5. Thermostat Off");
            System.out.println("6. Door Lock");
            System.out.println("7. Door Unlock");
            System.out.println("8. Clear slot");
            System.out.print("Choice: ");
            String c = sc.nextLine().trim();
            switch (c) {
                case "1": assignLightOn(slot); break;
                case "2": assignLightOff(slot); break;
                case "3": assignLightDim(slot); break;
                case "4": assignThermostatSet(slot); break;
                case "5": assignThermostatOff(slot); break;
                case "6": assignDoorLock(slot); break;
                case "7": assignDoorUnlock(slot); break;
                case "8": remote.clearSlot(slot); break;
                default: System.out.println("Invalid selection."); break;
            }
        }

        private void assignLightOn(int slot) {
            System.out.print("Light name: ");
            String name = sc.nextLine().trim();
            Light l = lights.get(name);
            if (l == null) { System.out.println("No such light."); return; }
            remote.setSlot(slot, new LightOnCommand(l, logger));
        }

        private void assignLightOff(int slot) {
            System.out.print("Light name: ");
            String name = sc.nextLine().trim();
            Light l = lights.get(name);
            if (l == null) { System.out.println("No such light."); return; }
            remote.setSlot(slot, new LightOffCommand(l, logger));
        }

        private void assignLightDim(int slot) {
            System.out.print("Light name: ");
            String name = sc.nextLine().trim();
            Light l = lights.get(name);
            if (l == null) { System.out.println("No such light."); return; }
            System.out.print("Brightness 0-100: ");
            int b = parseIntOrDefault(sc.nextLine().trim(), l.getBrightness());
            remote.setSlot(slot, new LightDimCommand(l, b, logger));
        }

        private void assignThermostatSet(int slot) {
            System.out.print("Thermostat name: ");
            String name = sc.nextLine().trim();
            Thermostat t = thermostats.get(name);
            if (t == null) { System.out.println("No such thermostat."); return; }
            System.out.print("Temperature (°C): ");
            double temp = parseDoubleOrDefault(sc.nextLine().trim(), t.getTemperature());
            remote.setSlot(slot, new ThermostatSetCommand(t, temp, logger));
        }

        private void assignThermostatOff(int slot) {
            System.out.print("Thermostat name: ");
            String name = sc.nextLine().trim();
            Thermostat t = thermostats.get(name);
            if (t == null) { System.out.println("No such thermostat."); return; }
            remote.setSlot(slot, new ThermostatOffCommand(t, logger));
        }

        private void assignDoorLock(int slot) {
            System.out.print("Door name: ");
            String name = sc.nextLine().trim();
            Door d = doors.get(name);
            if (d == null) { System.out.println("No such door."); return; }
            remote.setSlot(slot, new DoorLockCommand(d, logger));
        }

        private void assignDoorUnlock(int slot) {
            System.out.print("Door name: ");
            String name = sc.nextLine().trim();
            Door d = doors.get(name);
            if (d == null) { System.out.println("No such door."); return; }
            remote.setSlot(slot, new DoorUnlockCommand(d, logger));
        }

        // Macro creation menu (simple)
        private void scheduleMacroMenu() {
            System.out.print("Macro name (or 'back'): ");
            String name = sc.nextLine().trim();
            if (name.equalsIgnoreCase("back")) return;
            MacroCommand macro = new MacroCommand(name, logger);
            System.out.println("Add commands to macro. Type 'done' when finished.");
            while (true) {
                System.out.println("Add: 1) LightOn 2) LightOff 3) LightDim 4) ThermoSet 5) ThermoOff 6) DoorLock 7) DoorUnlock 8) done");
                System.out.print("Choice: ");
                String c = sc.nextLine().trim();
                if (c.equals("8") || c.equalsIgnoreCase("done")) break;
                switch (c) {
                    case "1": {
                        System.out.print("Light name: "); String ln = sc.nextLine().trim();
                        Light l = lights.get(ln); if (l==null) { System.out.println("No such light."); break;}
                        macro.add(new LightOnCommand(l, logger)); break;
                    }
                    case "2": {
                        System.out.print("Light name: "); String ln = sc.nextLine().trim();
                        Light l = lights.get(ln); if (l==null) { System.out.println("No such light."); break;}
                        macro.add(new LightOffCommand(l, logger)); break;
                    }
                    case "3": {
                        System.out.print("Light name: "); String ln = sc.nextLine().trim();
                        Light l = lights.get(ln); if (l==null) { System.out.println("No such light."); break;}
                        System.out.print("Brightness: "); int b = parseIntOrDefault(sc.nextLine().trim(), l.getBrightness());
                        macro.add(new LightDimCommand(l, b, logger)); break;
                    }
                    case "4": {
                        System.out.print("Thermostat name: "); String tn = sc.nextLine().trim();
                        Thermostat t = thermostats.get(tn); if (t==null) { System.out.println("No such thermo."); break;}
                        System.out.print("Temp: "); double tmp = parseDoubleOrDefault(sc.nextLine().trim(), t.getTemperature());
                        macro.add(new ThermostatSetCommand(t, tmp, logger)); break;
                    }
                    case "5": {
                        System.out.print("Thermostat name: "); String tn = sc.nextLine().trim();
                        Thermostat t = thermostats.get(tn); if (t==null) { System.out.println("No such thermo."); break;}
                        macro.add(new ThermostatOffCommand(t, logger)); break;
                    }
                    case "6": {
                        System.out.print("Door name: "); String dn = sc.nextLine().trim();
                        Door d = doors.get(dn); if (d==null) { System.out.println("No such door."); break;}
                        macro.add(new DoorLockCommand(d, logger)); break;
                    }
                    case "7": {
                        System.out.print("Door name: "); String dn = sc.nextLine().trim();
                        Door d = doors.get(dn); if (d==null) { System.out.println("No such door."); break;}
                        macro.add(new DoorUnlockCommand(d, logger)); break;
                    }
                    default: System.out.println("Unknown entry.");
                }
            }
            System.out.println("Macro created. Execute now? (y/n)");
            String exec = sc.nextLine().trim();
            if (exec.equalsIgnoreCase("y")) macro.execute();
            System.out.print("Assign macro to remote slot? (enter slot number or 'no'): ");
            String slot = sc.nextLine().trim();
            if (!slot.equalsIgnoreCase("no")) {
                int s = parseIntOrDefault(slot, -1);
                if (s>=0) remote.setSlot(s, macro);
            }
        }

        // View log/history
        private void viewHistoryMenu() {
            System.out.print("Show how many recent log lines? (default 20): ");
            String in = sc.nextLine().trim();
            int n = parseIntOrDefault(in, 20);
            List<String> lines = logger.recent(n);
            System.out.println("\n--- Recent logs ---");
            for (String l : lines) System.out.println(l);
        }

        private void shutdown() {
            logger.log("Shutting down SmartHomeCommandStandard application.");
            logger.close();
            System.out.println("Shutdown complete.");
        }

        // Utility helpers
        private void listKeys(Set<String> keys) {
            System.out.println("Available: " + String.join(", ", keys));
        }

        private static int parseIntOrDefault(String s, int def) {
            try { return Integer.parseInt(s); } catch (Exception e) { return def; }
        }

        private static double parseDoubleOrDefault(String s, double def) {
            try { return Double.parseDouble(s); } catch (Exception e) { return def; }
        }
    }

    // ---------------------------
    // Main
    // ---------------------------
    public static void main(String[] args) throws Exception {
        Logger logger = new Logger("smarthome_commands.log");
        ConsoleApp app = new ConsoleApp(logger);
        app.run();
    }
}