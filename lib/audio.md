# lib/audio.mg

Simple WAV/audio helpers for Magnetar (pure syscalls).

## Features
- WAV PCM load/save: 8/16-bit, mono/stereo (`audio_load_wav`, `audio_write_wav`)
- Clip creation: `audio_make_clip`, `audio_clip_free`, `audio_duration_ms`
- Tone/noise generation: `audio_tone`, `audio_beep`, `audio_generate_tone`, `audio_noise`
- Mixing: `audio_mix_into(dst, src, offset_frames)`
- Playback (best-effort, via system players): `audio_play_wav`, `audio_play_file`, `audio_play_clip`
  - tries `aplay`, then `paplay`, then `ffplay` (fork/exec)

## Example
```mg
use "lib/audio.mg";

fn main() -> int {
    AudioClip b = audio_beep();
    audio_write_wav("/tmp/beep.wav", &b);
    audio_play_wav("/tmp/beep.wav"); // blocking
    audio_clip_free(&b);
    return 0;
}
```

## Build/run demo
```sh
./magc examples/demo_audio.mg -o build/demo_audio
./build/demo_audio
```
