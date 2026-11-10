package com.example.aivision

import android.net.Uri
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import kotlin.math.abs

/** E02 against golden fixtures (fixtures/manifest.yaml). Software part of AC-003; QA-003 still needs a real tablet. */
@RunWith(AndroidJUnit4::class)
class FilePlaybackTest {
    private val instr = InstrumentationRegistry.getInstrumentation()

    private fun fixture(name: String): Uri {
        val out = File(instr.targetContext.cacheDir, name)
        instr.context.assets.open(name).use { i -> out.outputStream().use { i.copyTo(it) } }
        return Uri.fromFile(out)
    }

    @Suppress("UNCHECKED_CAST")
    private fun <T> main(block: () -> T): T { var r: Any? = null; instr.runOnMainSync { r = block() }; return r as T }

    private fun waitFor(timeoutMs: Long = 10_000, cond: () -> Boolean) {
        val end = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < end) { if (main(cond)) return; Thread.sleep(20) }
        fail("timed out")
    }

    @Test fun opensFixturesAndSeeksAccurately() {
        for (name in listOf("synth_en_1080p60_001.mp4", "synth_ja_1080p60_001.mp4")) {
            val uri = fixture(name)
            val c = main { PlayerController(instr.targetContext).also { it.open(uri) } }
            waitFor { c.state.value == PlayerController.LoadState.Ready }
            assertEquals(name, 12_000.0, main { c.durationMs }.toDouble(), 100.0)
            val fmt = main { c.player.videoFormat }!!
            assertEquals(1920, fmt.width); assertEquals(1080, fmt.height)
            assertEquals(60f, fmt.frameRate, 0.5f)
            val e0 = main { c.epoch.value }
            for (target in listOf(7_800L, 1_200L, 10_000L, 0L)) {
                main { c.seekTo(target) }
                waitFor { !c.player.isLoading && c.player.playbackState == androidx.media3.common.Player.STATE_READY &&
                    abs(c.positionMs - target) <= 17 }
            }
            assertEquals(e0 + 4uL, main { c.epoch.value })
            main { c.skip(-10_000) }; waitFor { c.positionMs == 0L }
            main { c.release() }
        }
    }

    @Test fun corruptFileFailsWithMessage() { // NFR-009
        val bad = File(instr.targetContext.cacheDir, "corrupt.mp4").apply { writeText("not a video") }
        val c = main { PlayerController(instr.targetContext).also { it.open(Uri.fromFile(bad)) } }
        waitFor { c.state.value is PlayerController.LoadState.Failed }
        assertNull(main { c.session })
        main { c.release() }
    }
}
