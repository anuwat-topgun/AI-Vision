package com.example.aivision

import android.content.Intent
import android.net.Uri
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.annotation.OptIn
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.util.UnstableApi
import androidx.media3.ui.PlayerView
import kotlinx.coroutines.delay

/** Containers offered in the picker; codec support is checked on open (FR-001). */
private val videoMimeTypes = arrayOf("video/mp4", "video/quicktime", "video/x-matroska", "video/*")

@OptIn(UnstableApi::class)
@Composable
fun FilePlayerScreen(onBack: () -> Unit) {
    val ctx = LocalContext.current
    val controller = remember { PlayerController(ctx) }
    DisposableEffect(Unit) { onDispose { controller.release() } }
    BackHandler(onBack = onBack)

    val state by controller.state.collectAsState()
    val epoch by controller.epoch.collectAsState()
    var fullscreen by remember { mutableStateOf(false) }
    var position by remember { mutableLongStateOf(0L) }
    var scrub by remember { mutableStateOf<Float?>(null) }
    var playing by remember { mutableStateOf(false) }
    var speed by remember { mutableFloatStateOf(1f) }
    var muted by remember { mutableStateOf(false) }

    // SAF picker: no raw filesystem paths (AC-003); persist read grant for Recent Files.
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri: Uri? ->
        uri ?: return@rememberLauncherForActivityResult
        runCatching { ctx.contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION) }
        controller.open(uri)
    }
    LaunchedEffect(Unit) { picker.launch(videoMimeTypes) }
    LaunchedEffect(state) {
        while (state == PlayerController.LoadState.Ready) {
            position = controller.positionMs; playing = controller.player.isPlaying
            delay(100)
        }
    }

    Column(Modifier.fillMaxSize().background(Color.Black)) {
        Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
            when (val s = state) {
                PlayerController.LoadState.Ready -> AndroidView(
                    factory = { PlayerView(it).apply { useController = false; player = controller.player } },
                    modifier = Modifier.fillMaxSize().semantics { contentDescription = "Video" }
                        .clickable { fullscreen = !fullscreen },
                )
                PlayerController.LoadState.Loading -> CircularProgressIndicator()
                is PlayerController.LoadState.Failed -> Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(s.message, color = Color.White, modifier = Modifier.padding(16.dp))
                    Button(onClick = { picker.launch(videoMimeTypes) }) { Text("Choose another file") }
                }
                PlayerController.LoadState.Idle ->
                    Button(onClick = { picker.launch(videoMimeTypes) }) { Text("Choose a video file") }
            }
        }
        if (state == PlayerController.LoadState.Ready && !fullscreen) {
            Surface(tonalElevation = 3.dp) {
                Column(Modifier.fillMaxWidth().padding(12.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(PlayerController.format(scrub?.toLong() ?: position))
                        Slider(
                            value = scrub ?: position.toFloat(),
                            onValueChange = { scrub = it },
                            onValueChangeFinished = { scrub?.let { controller.seekTo(it.toLong()) }; scrub = null },
                            valueRange = 0f..controller.durationMs.coerceAtLeast(1).toFloat(),
                            modifier = Modifier.weight(1f).padding(horizontal = 8.dp)
                                .semantics { contentDescription = "Playback position" },
                        )
                        Text(PlayerController.format(controller.durationMs))
                    }
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        TextButton(onClick = { controller.skip(-10_000) }) { Text("−10s") }
                        FilledTonalButton(onClick = { controller.togglePlay() }) { Text(if (playing) "Pause" else "Play") }
                        TextButton(onClick = { controller.skip(10_000) }) { Text("+10s") }
                        var menu by remember { mutableStateOf(false) }
                        Box {
                            TextButton(onClick = { menu = true }) { Text("${speed}×") }
                            DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                                PlayerController.speeds.forEach { sp ->
                                    DropdownMenuItem(text = { Text("${sp}×") },
                                        onClick = { speed = sp; controller.setSpeed(sp); menu = false })
                                }
                            }
                        }
                        TextButton(onClick = { muted = !muted; controller.player.volume = if (muted) 0f else 1f }) {
                            Text(if (muted) "Unmute" else "Mute")
                        }
                        TextButton(onClick = { fullscreen = true }) { Text("Fullscreen") }
                        Spacer(Modifier.weight(1f))
                        Text("epoch $epoch", style = MaterialTheme.typography.labelSmall)
                        TextButton(onClick = onBack) { Text("Close") }
                    }
                }
            }
        }
    }
}
