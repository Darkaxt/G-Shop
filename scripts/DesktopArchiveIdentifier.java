package com.retro.rshop;

import java.nio.file.*;
import java.nio.file.attribute.BasicFileAttributes;
import java.util.Map;

/** Windows entrypoint for the exact same bounded archive decoder as Android. */
public final class DesktopArchiveIdentifier {
    private static String json(Object value) {
        if (value instanceof Map) {
            StringBuilder out = new StringBuilder("{");
            for (Object item : ((Map<?, ?>) value).entrySet()) {
                Map.Entry<?, ?> entry = (Map.Entry<?, ?>) item;
                if (out.length() > 1) out.append(',');
                out.append(json(entry.getKey())).append(':').append(json(entry.getValue()));
            }
            return out.append('}').toString();
        }
        if (value instanceof Number) return value.toString();
        StringBuilder out = new StringBuilder("\"");
        for (char c : value.toString().toCharArray()) {
            if (c == '\\' || c == '"') out.append('\\').append(c);
            else if (c < 32) out.append(String.format("\\u%04x", (int)c));
            else out.append(c);
        }
        return out.append('"').toString();
    }
    public static void main(String[] args) throws Exception {
        if (args.length != 2) throw new IllegalArgumentException("platform archive");
        Path path = Path.of(args[1]);
        BasicFileAttributes before = Files.readAttributes(path, BasicFileAttributes.class,
                LinkOption.NOFOLLOW_LINKS);
        if (!before.isRegularFile() || Files.isSymbolicLink(path))
            throw new IllegalArgumentException("Not a regular archive");
        Map<String, Object> container = OwnedArchiveIdentity.container(path.toString());
        Map<String, Object> raw = OwnedN64SevenZip.validate(path.toString(), args[0]);
        BasicFileAttributes after = Files.readAttributes(path, BasicFileAttributes.class,
                LinkOption.NOFOLLOW_LINKS);
        if (!container.equals(OwnedArchiveIdentity.container(path.toString())) ||
                before.size() != after.size() || !before.lastModifiedTime().equals(after.lastModifiedTime()) ||
                !java.util.Objects.equals(before.fileKey(), after.fileKey()))
            throw new IllegalStateException("Archive changed while reading");
        System.out.println(json(Map.of("raw", raw, "container", container)));
    }
}
