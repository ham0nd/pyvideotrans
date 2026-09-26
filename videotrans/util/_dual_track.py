# -*- coding: utf-8 -*-
"""Utilities for deterministic two-party call transcription.

Supports both common recording layouts:
1. two independent audio streams (0:a:0 and 0:a:1)
2. one multichannel/stereo audio stream where channel 0/1 are different parties
"""

import json
from pathlib import Path

from videotrans.util._ffmpeg_runner import runffmpeg
from videotrans.util._ffprobe import runffprobe


def probe_dual_track(media_file: str) -> dict:
    """Inspect media and return how its first two parties can be extracted.

    Returns:
        {
            "mode": "streams" | "channels",
            "count": int,
            "audio_streams": int,
            "channels": int,
        }

    Raises:
        RuntimeError: if the file does not contain at least two separable tracks/channels.
    """
    raw = runffprobe([
        "-v", "error",
        "-print_format", "json",
        "-show_streams",
        media_file,
    ])
    data = json.loads(raw)
    audio_streams = [s for s in data.get("streams", []) if s.get("codec_type") == "audio"]

    if len(audio_streams) >= 2:
        return {
            "mode": "streams",
            "count": len(audio_streams),
            "audio_streams": len(audio_streams),
            "channels": 1,
        }

    if len(audio_streams) == 1:
        channels = int(audio_streams[0].get("channels") or 0)
        if channels >= 2:
            return {
                "mode": "channels",
                "count": channels,
                "audio_streams": 1,
                "channels": channels,
            }

    raise RuntimeError(
        "双轨通话模式需要两个独立音轨，或一个至少包含两个声道的音轨。"
        "当前文件未检测到可分离的两路声音。"
    )


def extract_dual_track_16k(media_file: str, track1_wav: str, track2_wav: str) -> dict:
    """Extract the first two parties as mono 16 kHz PCM WAV files."""
    info = probe_dual_track(media_file)

    Path(track1_wav).parent.mkdir(parents=True, exist_ok=True)
    Path(track2_wav).parent.mkdir(parents=True, exist_ok=True)

    common = ["-y", "-i", Path(media_file).as_posix()]

    if info["mode"] == "streams":
        runffmpeg(common + [
            "-map", "0:a:0",
            "-vn",
            "-ac", "1",
            "-ar", "16000",
            "-c:a", "pcm_s16le",
            Path(track1_wav).as_posix(),
        ])
        runffmpeg(common + [
            "-map", "0:a:1",
            "-vn",
            "-ac", "1",
            "-ar", "16000",
            "-c:a", "pcm_s16le",
            Path(track2_wav).as_posix(),
        ])
    else:
        # One stereo/multichannel stream: use channel 0 and channel 1 directly.
        runffmpeg(common + [
            "-map", "0:a:0",
            "-vn",
            "-af", "pan=mono|c0=c0",
            "-ar", "16000",
            "-c:a", "pcm_s16le",
            Path(track1_wav).as_posix(),
        ])
        runffmpeg(common + [
            "-map", "0:a:0",
            "-vn",
            "-af", "pan=mono|c0=c1",
            "-ar", "16000",
            "-c:a", "pcm_s16le",
            Path(track2_wav).as_posix(),
        ])

    return info
