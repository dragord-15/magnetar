// demo_audio.mg - Magnetar audio library demo
// Build: ./magc examples/demo_audio.mg -o build/demo_audio
// Run:   ./build/demo_audio

use "lib/audio.mg";

extern fn print_str(string s) -> void;
extern fn print_int(int n) -> void;

fn main() -> int {
    print_str("Magnetar Audio Demo\n");

    // Generate and save a beep tone
    AudioClip beep = audio_beep();
    if (beep.valid == 1) {
        print_str("Generated beep: ");
        print_int(audio_duration_ms(&beep));
        print_str(" ms\n");
        if (audio_write_wav("/tmp/mg_demo_beep.wav", &beep) == true) {
            print_str("Saved /tmp/mg_demo_beep.wav\n");
        }
    }

    // Generate a short melody sequence by mixing tones
    int sr = 44100;
    int ch = 1;
    int bits = 16;
    int total_ms = 1200;
    int frames = sr * total_ms / 1000;
    AudioClip song = audio_make_clip(sr, ch, bits, frames * ch * (bits / 8));
    AudioClip n1 = audio_generate_tone(440, 300, sr, ch, bits, 1, 50); // A4
    AudioClip n2 = audio_generate_tone(554, 300, sr, ch, bits, 1, 50); // C#5
    AudioClip n3 = audio_generate_tone(659, 300, sr, ch, bits, 1, 50); // E5
    AudioClip n4 = audio_generate_tone(880, 300, sr, ch, bits, 1, 50); // A5
    audio_mix_into(&song, &n1, 0);
    audio_mix_into(&song, &n2, sr * 300 / 1000);
    audio_mix_into(&song, &n3, sr * 600 / 1000);
    audio_mix_into(&song, &n4, sr * 900 / 1000);
    if (audio_write_wav("/tmp/mg_demo_song.wav", &song) == true) {
        print_str("Saved /tmp/mg_demo_song.wav\n");
    }

    // Try loading back
    AudioClip loaded = audio_load_wav("/tmp/mg_demo_beep.wav");
    if (loaded.valid == 1) {
        print_str("Loaded WAV: ");
        print_int(loaded.sample_rate);
        print_str(" Hz, ch=");
        print_int(loaded.channels);
        print_str(", bits=");
        print_int(loaded.bits_per_sample);
        print_str(", ");
        print_int(audio_duration_ms(&loaded));
        print_str(" ms\n");
    }

    print_str("Audio demo complete. Play files with: aplay /tmp/mg_demo_beep.wav\n");

    audio_clip_free(&beep);
    audio_clip_free(&n1);
    audio_clip_free(&n2);
    audio_clip_free(&n3);
    audio_clip_free(&n4);
    audio_clip_free(&song);
    audio_clip_free(&loaded);
    return 0;
}
