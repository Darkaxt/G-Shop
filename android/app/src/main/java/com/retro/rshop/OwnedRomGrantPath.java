package com.retro.rshop;

import java.io.FileNotFoundException;
import java.util.List;
import java.util.Locale;

/** Decodes only one committed installation leaf, never a public directory tree. */
final class OwnedRomGrantPath {
    private static final java.util.Set<String> COPY_PLATFORMS = new java.util.HashSet<>(java.util.Arrays.asList(
        "gamegear", "megadrive", "mastersystem", "sg1000", "n64", "gb", "gbc", "gba", "nes", "snes", "psx", "psp", "ps2", "wiiu", "gc", "wii", "nds"));
    final String installationId;
    final String filename;
    final boolean document;
    final Long observationId;
    final String platform;

    private OwnedRomGrantPath(String id, String name, boolean document,
            Long observationId, String platform) {
        installationId = id; filename = name; this.document = document;
        this.observationId = observationId; this.platform = platform;
    }

    static OwnedRomGrantPath parse(List<String> segments) throws FileNotFoundException {
        String id, name;
        boolean document;
        if (segments.size() == 3 && (segments.get(0).equals("installation") || segments.get(0).equals("copy"))) {
            id = segments.get(1); name = segments.get(2); document = false;
        } else if (segments.size() == 4 && segments.get(0).equals("tree") &&
                segments.get(2).equals("document")) {
            id = segments.get(1);
            String prefix = id + "/";
            if (!segments.get(3).startsWith(prefix)) throw invalid();
            name = segments.get(3).substring(prefix.length()); document = true;
        } else throw invalid();
        if (!leaf(id) || !leaf(name) || (document && name.indexOf('#') >= 0)) throw invalid();
        Long observationId = null;
        String platform = null;
        if (id.startsWith("copy:")) {
            String[] parts = id.split(":", -1);
            if (parts.length != 3 || !parts[1].matches("[1-9][0-9]*") ||
                    !COPY_PLATFORMS.contains(parts[2]) ||
                    (!document && !segments.get(0).equals("copy"))) throw invalid();
            try { observationId = Long.parseLong(parts[1]); }
            catch (NumberFormatException error) { throw invalid(); }
            platform = parts[2];
        } else if (!document && segments.get(0).equals("copy")) throw invalid();
        return new OwnedRomGrantPath(id, name, document, observationId, platform);
    }


    private static boolean leaf(String value) {
        if (value.isEmpty() || value.equals(".") || value.equals("..") ||
                value.indexOf('/') >= 0 || value.indexOf('\\') >= 0) return false;
        for (int i = 0; i < value.length(); i++) if (Character.isISOControl(value.charAt(i))) return false;
        return true;
    }

    static boolean standaloneChd(String filename, String archivePlatform,
            boolean bundleMember, int dependencies, int members) {
        return leaf(filename) && filename.toLowerCase(Locale.ROOT).endsWith(".chd") &&
            archivePlatform.isEmpty() && !bundleMember && dependencies == 0 && members == 0;
    }

    static boolean standaloneNds(String filename, String archivePlatform,
            boolean bundleMember, int dependencies, int members) {
        return leaf(filename) && filename.toLowerCase(Locale.ROOT).endsWith(".nds") &&
            archivePlatform.isEmpty() && !bundleMember && dependencies == 0 && members == 0;
    }

    static boolean standaloneWua(String filename, String archivePlatform,
            boolean bundleMember, int dependencies, int members) {
        return leaf(filename) && filename.toLowerCase(Locale.ROOT).endsWith(".wua") &&
            archivePlatform.isEmpty() && !bundleMember && dependencies == 0 && members == 0;
    }

    private static FileNotFoundException invalid() { return new FileNotFoundException("Invalid ROM grant"); }
}
