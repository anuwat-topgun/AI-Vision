#!/usr/bin/env python3
"""Generate synthetic, team-owned EN/JA subtitle fixtures (README §16.2, §22.2 step 4).

Invented dialogue on moving synthetic backgrounds; no game assets. Output:
fixtures/media/<id>.mp4 (H.264 High 1080p60 + AAC 48k) and fixtures/manifest.yaml
with exact subtitle PTS ranges and normalized bboxes measured from the rendered text.

A short 1 kHz beep plays at each subtitle onset for A/V-sync checks (§14.1).
Run: python3 -I fixtures/tools/generate_fixtures.py   (needs ffmpeg with libx264, Pillow)
"""
import hashlib, io, math, struct, subprocess, sys, wave
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
FONT = ROOT / "tools/fonts/NotoSansJP-VF.ttf"
FONT_SHA256 = "c2f3b4d463500a2ddcd3849cded1fceeb9fd6d1c32e6cbecd568453ba50fc68f"
FONT_URL = "https://github.com/google/fonts/raw/main/ofl/notosansjp/NotoSansJP%5Bwght%5D.ttf"
W, H, FPS, SECONDS, SR = 1920, 1080, 60, 12, 48000

FIXTURES = [
    {"id": "synth_en_1080p60_001", "language": "en", "style": "bottom_outline", "subs": [
        (1200, 3900, "We should reach the gate before dawn."),
        (4500, 7200, "Keep your lantern low. The guards are near."),
        (7800, 10800, "If we split up, meet me at the old well."),
    ]},
    {"id": "synth_ja_1080p60_001", "language": "ja", "style": "dialog_box", "subs": [
        (1600, 4200, "夜明けまでに門へ行こう。"),
        (4800, 7500, "灯りを低くして。見張りが近い。"),
        (8100, 11000, "はぐれたら、古い井戸で会おう。"),
    ]},
]


def sha256(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


def font(size: int) -> ImageFont.FreeTypeFont:
    if not FONT.exists():
        sys.exit(f"Missing {FONT}. Download (OFL): curl -L -o '{FONT}' '{FONT_URL}'")
    if sha256(FONT) != FONT_SHA256:
        sys.exit(f"Font hash mismatch for {FONT}")
    f = ImageFont.truetype(str(FONT), size)
    f.set_variation_by_axes([700])  # bold weight
    return f


def background(t: float) -> Image.Image:
    # Low-res moving gradient + drifting bars, upscaled: cheap, non-static, game-like.
    w, h = 96, 54
    img = Image.new("RGB", (w, h))
    px = img.load()
    for y in range(h):
        for x in range(w):
            r = int(60 + 50 * math.sin(x / 9 + t * 0.9))
            g = int(70 + 40 * math.sin(y / 7 - t * 0.6))
            b = int(110 + 60 * math.sin((x + y) / 13 + t * 0.4))
            px[x, y] = (r, g, b)
    img = img.resize((W, H), Image.BILINEAR)
    d = ImageDraw.Draw(img)
    for i in range(6):  # moving "scenery" bars behind the subtitle area
        x = int((i * 380 + t * 140) % (W + 300)) - 300
        d.rectangle([x, 300 + i * 90, x + 220, 360 + i * 90], fill=(30 + i * 20, 40, 60))
    return img


def layout(text: str, style: str, fnt):
    l, t, r, b = fnt.getbbox(text)
    tw, th = r - l, b - t
    x = (W - tw) // 2 - l
    y = int(H * 0.86) - th // 2 - t
    bbox_px = (x + l, y + t, x + r, y + b)
    return x, y, bbox_px


def render(fx, out: Path):
    fnt = font(54)
    subs = [(s, e, txt, layout(txt, fx["style"], fnt)) for s, e, txt in fx["subs"]]
    cmd = ["ffmpeg", "-v", "error", "-y",
           "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}", "-r", str(FPS), "-i", "-",
           "-i", str(out.with_suffix(".wav")),
           "-c:v", "libx264", "-preset", "medium", "-crf", "20", "-g", "60", "-bf", "2",
           "-pix_fmt", "yuv420p", "-threads", "1", "-x264-params", "threads=1",
           "-c:a", "aac", "-b:a", "128k", "-shortest",
           "-map_metadata", "-1", "-fflags", "+bitexact", "-flags:v", "+bitexact", "-flags:a", "+bitexact",
           "-movflags", "+faststart", str(out)]
    write_audio(out.with_suffix(".wav"), [s for s, _, _, _ in subs])
    p = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    for n in range(FPS * SECONDS):
        ms = n * 1000 / FPS
        img = background(n / FPS)
        d = ImageDraw.Draw(img)
        for s, e, txt, (x, y, bb) in subs:
            if s <= ms < e:
                if fx["style"] == "dialog_box":
                    d.rounded_rectangle([bb[0] - 40, bb[1] - 28, bb[2] + 40, bb[3] + 28], 18,
                                        fill=(10, 10, 30), outline=(220, 220, 255), width=4)
                    d.text((x, y), txt, font=fnt, fill=(255, 255, 255))
                else:
                    d.text((x, y), txt, font=fnt, fill=(255, 255, 255), stroke_width=5, stroke_fill=(0, 0, 0))
        p.stdin.write(img.tobytes())
    p.stdin.close()
    if p.wait():
        sys.exit("ffmpeg failed")
    out.with_suffix(".wav").unlink()
    pad = 5  # outline stroke
    return [{"start_ms": s, "end_ms": e, "text": txt,
             "normalized_bbox": [round((bb[0] - pad) / W, 4), round((bb[1] - pad) / H, 4),
                                 round((bb[2] - bb[0] + 2 * pad) / W, 4), round((bb[3] - bb[1] + 2 * pad) / H, 4)]}
            for s, e, txt, (_, _, bb) in subs]


def write_audio(path: Path, onsets_ms):
    n = SR * SECONDS
    beeps = [(int(o * SR / 1000), int(o * SR / 1000) + SR // 20) for o in onsets_ms]  # 50 ms
    buf = io.BytesIO()
    for i in range(n):
        v = 0.0
        for a, b in beeps:
            if a <= i < b:
                v = 0.5 * math.sin(2 * math.pi * 1000 * (i - a) / SR)
        buf.write(struct.pack("<h", int(v * 32767)))
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(buf.getvalue())


def yaml_str(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main():
    ff = subprocess.run(["ffmpeg", "-version"], capture_output=True, text=True).stdout.split("\n")[0]
    lines = ["manifest_version: 2",
             'notice: "Synthetic, team-owned fixtures only. Never commit commercial game footage without documented permission."',
             f"generator: fixtures/tools/generate_fixtures.py",
             f"generator_ffmpeg: {yaml_str(ff)}",
             'font: {name: "Noto Sans JP (variable, wght=700)", license: "SIL OFL 1.1", sha256: "' + FONT_SHA256 + '"}',
             "fixtures:"]
    for fx in FIXTURES:
        out = ROOT / "media" / f"{fx['id']}.mp4"
        out.parent.mkdir(exist_ok=True)
        print("rendering", out.name, flush=True)
        subs = render(fx, out)
        lines += [f"  - id: {fx['id']}", f"    path: media/{out.name}", "    owner: engineering-team",
                  "    license: internal-owned (synthetic; font OFL-1.1)", f"    language: {fx['language']}",
                  f"    style: {fx['style']}", "    container: mp4", "    codec: h264", "    audio: aac",
                  f"    width: {W}", f"    height: {H}", f"    fps: {FPS}", f"    duration_ms: {SECONDS * 1000}",
                  "    audio_markers: 1kHz 50ms beep at each subtitle start_ms",
                  f"    sha256: {sha256(out)}", "    redistribution: allowed", "    expected_subtitles:"]
        for s in subs:
            lines += [f"      - start_ms: {s['start_ms']}", f"        end_ms: {s['end_ms']}",
                      f"        text: {yaml_str(s['text'])}", f"        normalized_bbox: {s['normalized_bbox']}"]
    (ROOT / "manifest.yaml").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("wrote manifest.yaml")


if __name__ == "__main__":
    main()
