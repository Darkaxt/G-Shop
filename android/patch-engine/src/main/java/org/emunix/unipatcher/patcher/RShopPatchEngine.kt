package org.emunix.unipatcher.patcher

import org.emunix.unipatcher.helpers.ResourceProvider
import org.emunix.unipatcher.utils.FileUtils
import org.emunix.unipatcher.utils.PatchCancellation
import java.io.File

/** No downloaded executable, checksum bypass or implicit arbitrary patch chain. */
object RShopPatchEngine {
    const val REVISION = "6f44fa5522f7606e73adc28f2601ef441c164d96-rshop1"
    @JvmStatic fun apply(format: String, patch: File, base: File, output: File,
            resources: ResourceProvider, preprocessing: List<String>) {
        PatchCancellation.check()
        require(base.canonicalPath != output.canonicalPath &&
            patch.canonicalPath != output.canonicalPath && !output.exists())
        // EBP's source format includes original-ROM repairs. These are declared
        // in the recipe and must be explicitly selected, never silently enabled.
        require(if (format == "ebp") preprocessing == listOf("ebp-canonical-base")
            else preprocessing.isEmpty())
        val io = FileUtils()
        val engine = when (format) {
            "ips", "ips32" -> IPS(patch, base, output, resources, io)
            "ups" -> UPS(patch, base, output, resources, io)
            "bps" -> BPS(patch, base, output, resources, io)
            "aps" -> APS(patch, base, output, resources, io)
            "ppf" -> PPF(patch, base, output, resources, io)
            "dps" -> DPS(patch, base, output, resources, io)
            "ebp" -> EBP(patch, base, output, resources, io)
            "xdelta" -> XDelta(patch, base, output, resources, io)
            else -> throw IllegalArgumentException("unsupported_patch_format")
        }
        try { engine.apply(false) } finally { io.requireClosed() }
        PatchCancellation.check()
        require(output.isFile && output.length() > 0)
    }
}
