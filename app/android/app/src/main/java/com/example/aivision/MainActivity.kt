package com.example.aivision

import android.os.Bundle
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import uniffi.subtitle_ffi.coreApiVersion

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val version = coreApiVersion()
        setContent {
            MaterialTheme {
                var screen by rememberSaveable { mutableStateOf("home") }
                when (screen) {
                    "file" -> FilePlayerScreen(onBack = { screen = "home" })
                    else -> HomeScreen(version, onOpenFile = { screen = "file" })
                }
            }
        }
    }
}

/** Home: File and Live Capture visibly separate (README §11.2). File Input is permanent (ADR-0003, AC-004). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen(coreVersion: UInt, onOpenFile: () -> Unit) {
    val ctx = LocalContext.current
    val todo = { msg: String -> Toast.makeText(ctx, msg, Toast.LENGTH_SHORT).show() }
    Scaffold(
        topBar = { TopAppBar(title = { Text("AI Vision — EN/JA → ไทย") }) },
        bottomBar = {
            Text("Offline mode · Cloud off · core API v$coreVersion",
                Modifier.fillMaxWidth().padding(12.dp), textAlign = TextAlign.Center)
        },
    ) { pad ->
        BoxWithConstraints(Modifier.padding(pad).padding(16.dp)) {
            val tiles = @Composable { m: Modifier ->
                ModeTile(m.testTag("tile_file"), Icons.Filled.PlayArrow, "Video File / ไฟล์วิดีโอ",
                    "MP4 / MOV / MKV (where supported)") { onOpenFile() }
                ModeTile(m.testTag("tile_live"), Icons.Filled.Settings, "Live Capture / จับภาพสด",
                    "UVC capture card — qualified devices only") { todo("UVC adapter not implemented yet (E08)") }
            }
            if (maxWidth > 700.dp) Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) { tiles(Modifier.weight(1f)) }
            else Column(verticalArrangement = Arrangement.spacedBy(16.dp)) { tiles(Modifier.fillMaxWidth()) }
        }
    }
}

@Composable
fun ModeTile(modifier: Modifier, icon: ImageVector, title: String, subtitle: String, onClick: () -> Unit) {
    ElevatedCard(onClick = onClick, modifier = modifier.heightIn(min = 200.dp)) {
        Column(Modifier.fillMaxWidth().padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(icon, contentDescription = title, Modifier.size(56.dp))
            Spacer(Modifier.height(12.dp))
            Text(title, style = MaterialTheme.typography.titleLarge, textAlign = TextAlign.Center)
            Text(subtitle, textAlign = TextAlign.Center)
        }
    }
}
