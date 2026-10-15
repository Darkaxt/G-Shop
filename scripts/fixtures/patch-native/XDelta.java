package org.emunix.unipatcher.patcher;

import java.io.File;
import java.nio.file.Files;
import java.util.Arrays;

/** Standalone ADB fixture for the actual APK's JNI decoder, not an app entrypoint. */
public final class XDelta {
  private native int xdelta3apply(String patch, String original, String output, boolean ignoreChecksum);
  public static void main(String[] args) throws Exception {
    if (args.length != 2) throw new IllegalArgumentException("library and fixture roots required");
    File directory = new File(args[1]).getCanonicalFile();
    if (!directory.getPath().equals("/storage/emulated/0/RShopPatchProbe-20261015")) {
      throw new IllegalArgumentException("unexpected fixture root");
    }
    System.load(new File(args[0], "liblzma.so").getPath());
    System.load(new File(args[0], "libxdelta3.so").getPath());
    File original = new File(directory, "original.bin");
    File patch = new File(directory, "copy-add.vcdiff");
    File corrupt = new File(directory, "corrupt.vcdiff");
    File output = new File(directory, "result.bin");
    for (File file : new File[]{original, patch, corrupt, output}) {
      if (file.exists()) throw new IllegalStateException("fixture already exists");
    }
    byte[] base = new byte[]{1, 2, 3, 4};
    // RFC3284 default table: COPY 2 from source offset 0, ADD 9, COPY 1
    // from source offset 3. No external patch executable or copyrighted bytes.
    byte[] delta = new byte[]{(byte)0xd6, (byte)0xc3, (byte)0xc4, 0, 0,
        1, 4, 0, 13, 4, 0, 1, 5, 2, 9, 19, 2, 2, 19, 1, 0, 3};
    Files.write(original.toPath(), base);
    Files.write(patch.toPath(), delta);
    Files.write(corrupt.toPath(), new byte[]{1, 2, 3, 4, 5});
    XDelta decoder = new XDelta();
    int before = new File("/proc/self/fd").list().length;
    for (int i = 0; i < 64; i++) {
      int code = decoder.xdelta3apply(patch.getPath(), new File(directory, "absent.bin").getPath(),
          new File(directory, "absent-output.bin").getPath(), false);
      if (code != -5002) throw new IllegalStateException("missing source not rejected: " + code);
    }
    int after = new File("/proc/self/fd").list().length;
    if (after > before + 1) throw new IllegalStateException("native descriptor leak");
    int code = decoder.xdelta3apply(patch.getPath(), original.getPath(), output.getPath(), false);
    if (code != 0 || !Arrays.equals(Files.readAllBytes(output.toPath()), new byte[]{1, 2, 9, 4})) {
      throw new IllegalStateException("copy/add decode failed: " + code);
    }
    int rejected = decoder.xdelta3apply(corrupt.getPath(), original.getPath(),
        new File(directory, "rejected.bin").getPath(), false);
    if (rejected == 0) throw new IllegalStateException("corrupt delta accepted");
    if (!Arrays.equals(Files.readAllBytes(original.toPath()), base)) {
      throw new IllegalStateException("original changed");
    }
    System.out.println("{\"format\":\"xdelta3-vcdiff\",\"copyAddVerified\":true,"
        + "\"corruptionRejected\":true,\"originalPreserved\":true,\"descriptorDelta\":" + (after-before) + "}");
  }
}
