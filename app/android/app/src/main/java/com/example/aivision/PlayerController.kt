package com.example.aivision

import android.content.Context
import android.net.Uri
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.exoplayer.SeekParameters
import androidx.media3.exoplayer.ExoPlayer
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import uniffi.subtitle_ffi.CoreSession
import uniffi.subtitle_ffi.FfiEpochReason
import java.util.UUID

/**
 * File playback controller (E02, FR-001/FR-002, AC-003).
 * Video renders to a native Surface via Media3; frames never enter Rust or Compose state.
 * Every seek / new file bumps the Rust session epoch (README §4.3, §10.3).
 * Must be used from the main thread (ExoPlayer requirement).
 */
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
class PlayerController(context: Context) {
    sealed interface LoadState {
        data object Idle : LoadState
        data object Loading : LoadState
        data object Ready : LoadState
        data class Failed(val message: String) : LoadState
    }

    val player: ExoPlayer = ExoPlayer.Builder(context).build().apply {
        setSeekParameters(SeekParameters.EXACT)
    }
    private val _state = MutableStateFlow<LoadState>(LoadState.Idle)
    val state: StateFlow<LoadState> = _state
    private val _epoch = MutableStateFlow(0uL)
    val epoch: StateFlow<ULong> = _epoch
    var session: CoreSession? = null
        private set

    init {
        player.addListener(object : Player.Listener {
            override fun onPlaybackStateChanged(playbackState: Int) {
                if (playbackState == Player.STATE_READY && _state.value == LoadState.Loading) {
                    session = CoreSession("file:${UUID.randomUUID()}") // opaque id, never a raw path (§19.1(6))
                    _epoch.value = session!!.epoch()
                    _state.value = LoadState.Ready
                }
            }
            override fun onPlayerError(error: PlaybackException) {
                _state.value = LoadState.Failed(describe(error))
            }
        })
    }

    fun open(uri: Uri) {
        close()
        _state.value = LoadState.Loading
        player.setMediaItem(MediaItem.fromUri(uri))
        player.prepare()
    }

    val durationMs: Long get() = player.duration.takeIf { it != C.TIME_UNSET } ?: 0L
    val positionMs: Long get() = player.currentPosition

    fun togglePlay() { if (player.isPlaying) player.pause() else player.play() }

    fun setSpeed(speed: Float) = player.setPlaybackSpeed(speed)

    /** Seek invalidates in-flight AI work for the old position (AC-010). */
    fun seekTo(ms: Long) {
        val target = ms.coerceIn(0L, durationMs)
        session?.let { _epoch.value = it.bump(FfiEpochReason.SEEK) }
        player.seekTo(target)
    }

    fun skip(deltaMs: Long) = seekTo(positionMs + deltaMs)

    fun close() {
        player.stop()
        player.clearMediaItems()
        session?.destroy()
        session = null
        _state.value = LoadState.Idle
    }

    fun release() { close(); player.release() }

    /** NFR-009: tell unsupported format apart from IO/permission problems. */
    private fun describe(e: PlaybackException): String = when (e.errorCode) {
        PlaybackException.ERROR_CODE_DECODER_INIT_FAILED,
        PlaybackException.ERROR_CODE_DECODING_FORMAT_UNSUPPORTED,
        PlaybackException.ERROR_CODE_DECODING_FORMAT_EXCEEDS_CAPABILITIES ->
            "Unsupported file: this device can't decode its video format."
        PlaybackException.ERROR_CODE_PARSING_CONTAINER_MALFORMED,
        PlaybackException.ERROR_CODE_PARSING_CONTAINER_UNSUPPORTED ->
            "Unsupported or damaged file."
        PlaybackException.ERROR_CODE_IO_NO_PERMISSION, PlaybackException.ERROR_CODE_IO_FILE_NOT_FOUND ->
            "Can't read this file. Choose it again to grant access."
        PlaybackException.ERROR_CODE_DRM_UNSPECIFIED, PlaybackException.ERROR_CODE_DRM_CONTENT_ERROR ->
            "This file is DRM-protected and can't be played."
        else -> "Couldn't play the file (${e.errorCodeName})."
    }

    companion object {
        val speeds = listOf(0.5f, 0.75f, 1f, 1.25f, 1.5f, 2f)
        fun format(ms: Long): String { val s = ms / 1000; return "%d:%02d".format(s / 60, s % 60) }
    }
}
