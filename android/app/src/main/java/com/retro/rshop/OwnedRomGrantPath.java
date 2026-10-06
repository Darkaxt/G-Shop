package com.retro.rshop;

import java.io.FileNotFoundException;
import java.util.List;
import java.util.Locale;

/** Decodes only one committed installation leaf, never a public directory tree. */
final class OwnedRomGrantPath {
    final String installationId;
    final String filename;
    final boolean document;

    private OwnedRomGrantPath(String id, String name, boolean document) {
        installationId = id; filename = name; this.document = document;
    }

    static OwnedRomGrantPath parse(List<String> segments) throws FileNotFoundException {
        String id, name;
        boolean document;
        if (segments.size() == 3 && segments.get(0).equals("installation")) {
            id = segments.get(1); name = segments.get(2); document = false;
        } else if (segments.size() == 4 && segments.get(0).equals("tree") &&
                segments.get(2).equals("document")) {
            id = segments.get(1);
            String prefix = id + "/";
            if (!segments.get(3).startsWith(prefix)) throw invalid();
            name = segments.get(3).substring(prefix.length()); document = true;
        } else throw invalid();
        if (!leaf(id) || !leaf(name) || (document && name.indexOf('#') >= 0)) throw invalid();
        return new OwnedRomGrantPath(id, name, document);
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

    private static FileNotFoundException invalid() { return new FileNotFoundException("Invalid ROM grant"); }
}
