// ============================================================================
// Magnetar Audio Library (lib/audio.mg)
// Simple sound/audio helpers for games and apps.
//
// Features:
//   - WAV (RIFF/WAVE PCM 8/16-bit, mono/stereo) load/save
//   - Tone/square/noise generation and mixing
//   - Playback via system players (aplay, paplay, ffplay) using fork/exec
//
// Notes:
//   - Playback is best-effort and depends on available system audio tools.
//   - Pure Magnetar (syscalls), no external libs.
// ============================================================================

extern fn sys_open(string path, int flags, int mode) -> int;
extern fn sys_close(int fd) -> int;
extern fn sys_read(int fd, char* buf, int count) -> int;
extern fn sys_write(int fd, char* data, int count) -> int;
extern fn sys_unlink(string path) -> int;
extern fn sys_fork() -> int;
extern fn sys_execve(string path, char** argv, char** envp) -> int;
extern fn sys_wait4(int pid, int* wstatus, int options, char* rusage) -> int;
extern fn sys_exit(int code) -> void;

const int AUDIO_O_RDONLY = 0;
const int AUDIO_O_WRITE  = 577;
const int AUDIO_PERM     = 420;

struct AudioClip {
    char* data;
    int data_size;
    int sample_rate;
    int channels;
    int bits_per_sample;
    int valid;
};

struct AudioEnv {
    char** envp;
    int loaded;
}

static AudioEnv AUDIO_ENV;

fn _au_byte(char* p, int i) -> int {
    int v = cast<int>(*(p + i));
    if (v < 0) { v = v + 256; }
    return v;
}

fn _au_wr16(char* p, int off, int v) -> void {
    *(p + off) = cast<char>(v & 255);
    *(p + off + 1) = cast<char>((v / 256) & 255);
}

fn _au_wr32(char* p, int off, int v) -> void {
    *(p + off) = cast<char>(v & 255);
    *(p + off + 1) = cast<char>((v / 256) & 255);
    *(p + off + 2) = cast<char>((v / 65536) & 255);
    *(p + off + 3) = cast<char>((v / 16777216) & 255);
}

fn _au_rd16(char* p, int off) -> int {
    return _au_byte(p, off) + _au_byte(p, off + 1) * 256;
}

fn _au_rd32(char* p, int off) -> int {
    return _au_byte(p, off) + _au_byte(p, off + 1) * 256 + _au_byte(p, off + 2) * 65536 + _au_byte(p, off + 3) * 16777216;
}

fn _au_eq4(char* p, int off, int a, int b, int c, int d) -> bool {
    if (_au_byte(p, off) != a) { return false; }
    if (_au_byte(p, off + 1) != b) { return false; }
    if (_au_byte(p, off + 2) != c) { return false; }
    if (_au_byte(p, off + 3) != d) { return false; }
    return true;
}

fn audio_init_env() -> void {
    if (AUDIO_ENV.loaded == 1) { return; }
    AUDIO_ENV.envp = alloc<char*>(8);
    AUDIO_ENV.envp[0] = cast<char*>("PATH=/usr/local/bin:/usr/bin:/bin");
    AUDIO_ENV.envp[1] = cast<char*>("HOME=/tmp");
    AUDIO_ENV.envp[2] = null;
    AUDIO_ENV.loaded = 1;
}

fn audio_clip_init(AudioClip* c) -> void {
    c.data = null;
    c.data_size = 0;
    c.sample_rate = 44100;
    c.channels = 1;
    c.bits_per_sample = 16;
    c.valid = 0;
}

fn audio_clip_free(AudioClip* c) -> void {
    if (c.data != null) {
        if (c.data_size > 0) { free(c.data); }
    }
    c.data = null;
    c.data_size = 0;
    c.valid = 0;
}

fn audio_make_clip(int sample_rate, int channels, int bits_per_sample, int data_size) -> AudioClip {
    AudioClip c;
    audio_clip_init(&c);
    if (sample_rate <= 0) { sample_rate = 44100; }
    if (channels < 1) { channels = 1; }
    if (channels > 2) { channels = 2; }
    if (bits_per_sample != 8) {
        if (bits_per_sample != 16) { bits_per_sample = 16; }
    }
    if (data_size < 0) { data_size = 0; }
    c.sample_rate = sample_rate;
    c.channels = channels;
    c.bits_per_sample = bits_per_sample;
    c.data_size = data_size;
    if (data_size > 0) {
        c.data = alloc<char>(data_size);
        int i = 0;
        while (i < data_size) {
            *(c.data + i) = 0;
            i = i + 1;
        }
    }
    c.valid = 1;
    return c;
}

fn audio_duration_ms(AudioClip* c) -> int {
    if (c.valid == 0) { return 0; }
    if (c.sample_rate <= 0) { return 0; }
    int frame_size = c.channels * (c.bits_per_sample / 8);
    if (frame_size <= 0) { return 0; }
    int frames = c.data_size / frame_size;
    return frames * 1000 / c.sample_rate;
}

fn audio_write_wav(string path, AudioClip* c) -> bool {
    if (c.valid == 0) { return false; }
    if (c.data == null) { return false; }
    if (c.data_size <= 0) { return false; }
    int fd = sys_open(path, AUDIO_O_WRITE, AUDIO_PERM);
    if (fd < 0) { return false; }
    int byte_rate = c.sample_rate * c.channels * c.bits_per_sample / 8;
    int block_align = c.channels * c.bits_per_sample / 8;
    int chunk_size = 36 + c.data_size;
    char* h = alloc<char>(44);
    int i = 0;
    while (i < 44) { *(h + i) = 0; i = i + 1; }
    *(h + 0) = 82; *(h + 1) = 73; *(h + 2) = 70; *(h + 3) = 70;
    _au_wr32(h, 4, chunk_size);
    *(h + 8) = 87; *(h + 9) = 65; *(h + 10) = 86; *(h + 11) = 69;
    *(h + 12) = 102; *(h + 13) = 109; *(h + 14) = 116; *(h + 15) = 32;
    _au_wr32(h, 16, 16);
    _au_wr16(h, 20, 1);
    _au_wr16(h, 22, c.channels);
    _au_wr32(h, 24, c.sample_rate);
    _au_wr32(h, 28, byte_rate);
    _au_wr16(h, 32, block_align);
    _au_wr16(h, 34, c.bits_per_sample);
    *(h + 36) = 100; *(h + 37) = 97; *(h + 38) = 116; *(h + 39) = 97;
    _au_wr32(h, 40, c.data_size);
    int w1 = sys_write(fd, h, 44);
    int w2 = sys_write(fd, c.data, c.data_size);
    sys_close(fd);
    free(h);
    if (w1 != 44) { return false; }
    if (w2 != c.data_size) { return false; }
    return true;
}

fn audio_load_wav(string path) -> AudioClip {
    AudioClip c;
    audio_clip_init(&c);
    int fd = sys_open(path, AUDIO_O_RDONLY, 0);
    if (fd < 0) { return c; }

    int cap = 65536;
    char* all = alloc<char>(cap);
    int total = 0;
    while (true) {
        if (total + 4096 > cap) {
            int ncap = cap * 2;
            char* nb = alloc<char>(ncap);
            int k = 0;
            while (k < total) { *(nb + k) = *(all + k); k = k + 1; }
            free(all);
            all = nb;
            cap = ncap;
        }
        int r = sys_read(fd, all + total, 4096);
        if (r <= 0) { break; }
        total = total + r;
        if (total > 33554432) { break; }
    }
    sys_close(fd);

    if (total < 44) { free(all); return c; }
    if (!_au_eq4(all, 0, 82,73,70,70)) { free(all); return c; }
    if (!_au_eq4(all, 8, 87,65,86,69)) { free(all); return c; }

    int pos = 12;
    int fmt_ok = 0;
    int channels = 1;
    int sample_rate = 44100;
    int bits = 16;
    int audio_format = 1;
    int data_off = -1;
    int data_size = 0;

    while (pos + 8 <= total) {
        int csz = _au_rd32(all, pos + 4);
        if (_au_eq4(all, pos, 102,109,116,32)) {
            audio_format = _au_rd16(all, pos + 8);
            channels = _au_rd16(all, pos + 10);
            sample_rate = _au_rd32(all, pos + 12);
            bits = _au_rd16(all, pos + 22);
            fmt_ok = 1;
        } else {
            if (_au_eq4(all, pos, 100,97,116,97)) {
                data_off = pos + 8;
                data_size = csz;
                break;
            }
        }
        int adv = csz;
        if (adv < 0) { break; }
        if (adv % 2 == 1) { adv = adv + 1; }
        pos = pos + 8 + adv;
    }

    if (fmt_ok == 1) {
        if (data_off >= 0) {
            if (audio_format == 1) {
                if (bits == 8 || bits == 16) {
                    if (channels == 1 || channels == 2) {
                        if (data_off + data_size > total) { data_size = total - data_off; }
                        if (data_size > 0) {
                            c.sample_rate = sample_rate;
                            c.channels = channels;
                            c.bits_per_sample = bits;
                            c.data_size = data_size;
                            c.data = alloc<char>(data_size);
                            int k = 0;
                            while (k < data_size) {
                                *(c.data + k) = *(all + data_off + k);
                                k = k + 1;
                            }
                            c.valid = 1;
                        }
                    }
                }
            }
        }
    }
    free(all);
    return c;
}

fn audio_generate_tone(int freq_hz, int duration_ms, int sample_rate, int channels, int bits, int wave, int volume) -> AudioClip {
    if (freq_hz <= 0) { freq_hz = 440; }
    if (duration_ms <= 0) { duration_ms = 200; }
    if (sample_rate <= 0) { sample_rate = 44100; }
    if (channels < 1) { channels = 1; }
    if (channels > 2) { channels = 2; }
    if (bits != 8) {
        if (bits != 16) { bits = 16; }
    }
    if (volume < 0) { volume = 0; }
    if (volume > 100) { volume = 100; }
    int frames = sample_rate * duration_ms / 1000;
    int frame_size = channels * (bits / 8);
    int data_size = frames * frame_size;
    AudioClip c = audio_make_clip(sample_rate, channels, bits, data_size);
    if (c.valid == 0) { return c; }

    int period = sample_rate / freq_hz;
    if (period < 1) { period = 1; }
    int halfp = period / 2;
    int amp16 = 32767 * volume / 100;
    int amp8 = 127 * volume / 100;

    int i = 0;
    while (i < frames) {
        int ph = i - (i / period) * period;
        int sample16 = amp16;
        int sample8u = 128 + amp8;
        if (ph >= halfp) {
            sample16 = 0 - amp16;
            sample8u = 128 - amp8;
        }
        if (wave == 2) {
            int r = (i * 1103515245 + 12345);
            if (r < 0) { r = 0 - r; }
            int rv = r - (r / 65536) * 65536;
            sample16 = (rv - 32768) * volume / 100;
            sample8u = (rv / 256);
        }

        int ch = 0;
        while (ch < channels) {
            int off = (i * channels + ch) * (bits / 8);
            if (bits == 16) {
                int v = sample16;
                if (v < 0) { v = v + 65536; }
                *(c.data + off) = cast<char>(v & 255);
                *(c.data + off + 1) = cast<char>((v / 256) & 255);
            } else {
                *(c.data + off) = cast<char>(sample8u & 255);
            }
            ch = ch + 1;
        }
        i = i + 1;
    }
    return c;
}

fn audio_tone(int freq_hz, int duration_ms) -> AudioClip {
    return audio_generate_tone(freq_hz, duration_ms, 44100, 1, 16, 1, 60);
}

fn audio_beep() -> AudioClip {
    return audio_generate_tone(880, 120, 44100, 1, 16, 1, 60);
}

fn audio_noise(int duration_ms, int volume) -> AudioClip {
    return audio_generate_tone(440, duration_ms, 44100, 1, 16, 2, volume);
}

fn audio_mix_into(AudioClip* dst, AudioClip* src, int offset_frames) -> void {
    if (dst.valid == 0) { return; }
    if (src.valid == 0) { return; }
    if (dst.sample_rate != src.sample_rate) { return; }
    if (dst.channels != src.channels) { return; }
    if (dst.bits_per_sample != src.bits_per_sample) { return; }
    int frame_size = dst.channels * (dst.bits_per_sample / 8);
    if (frame_size <= 0) { return; }
    int dst_frames = dst.data_size / frame_size;
    int src_frames = src.data_size / frame_size;
    int i = 0;
    while (i < src_frames) {
        int di = offset_frames + i;
        if (di >= 0) {
            if (di < dst_frames) {
                int soff = i * frame_size;
                int doff = di * frame_size;
                if (dst.bits_per_sample == 16) {
                    int ch = 0;
                    while (ch < dst.channels) {
                        int s16 = _au_byte(src.data, soff + ch*2) + cast<int>(*(src.data + soff + ch*2 + 1)) * 256;
                        if (s16 >= 32768) { s16 = s16 - 65536; }
                        int d16 = _au_byte(dst.data, doff + ch*2) + cast<int>(*(dst.data + doff + ch*2 + 1)) * 256;
                        if (d16 >= 32768) { d16 = d16 - 65536; }
                        int m = s16 + d16;
                        if (m > 32767) { m = 32767; }
                        if (m < -32768) { m = -32768; }
                        int mv = m;
                        if (mv < 0) { mv = mv + 65536; }
                        *(dst.data + doff + ch*2) = cast<char>(mv & 255);
                        *(dst.data + doff + ch*2 + 1) = cast<char>((mv / 256) & 255);
                        ch = ch + 1;
                    }
                } else {
                    int ch = 0;
                    while (ch < dst.channels) {
                        int m = _au_byte(src.data, soff + ch) + _au_byte(dst.data, doff + ch) - 128;
                        if (m < 0) { m = 0; }
                        if (m > 255) { m = 255; }
                        *(dst.data + doff + ch) = cast<char>(m);
                        ch = ch + 1;
                    }
                }
            }
        }
        i = i + 1;
    }
}

fn _au_exec_aplay(string path) -> void {
    char** argv = alloc<char*>(8);
    argv[0] = cast<char*>("aplay");
    argv[1] = cast<char*>("-q");
    argv[2] = cast<char*>(path);
    argv[3] = null;
    sys_execve("/usr/bin/aplay", argv, AUDIO_ENV.envp);
    sys_execve("/bin/aplay", argv, AUDIO_ENV.envp);
}

fn _au_exec_paplay(string path) -> void {
    char** argv = alloc<char*>(8);
    argv[0] = cast<char*>("paplay");
    argv[1] = cast<char*>(path);
    argv[2] = null;
    sys_execve("/usr/bin/paplay", argv, AUDIO_ENV.envp);
    sys_execve("/bin/paplay", argv, AUDIO_ENV.envp);
}

fn _au_exec_ffplay(string path) -> void {
    char** argv = alloc<char*>(8);
    argv[0] = cast<char*>("ffplay");
    argv[1] = cast<char*>("-nodisp");
    argv[2] = cast<char*>("-autoexit");
    argv[3] = cast<char*>("-loglevel");
    argv[4] = cast<char*>("quiet");
    argv[5] = cast<char*>(path);
    argv[6] = null;
    sys_execve("/usr/bin/ffplay", argv, AUDIO_ENV.envp);
    sys_execve("/bin/ffplay", argv, AUDIO_ENV.envp);
}

fn _au_try_player(string player, string path, int wait) -> int {
    audio_init_env();
    int pid = sys_fork();
    if (pid < 0) { return -1; }
    if (pid == 0) {
        if (_au_byte(cast<char*>(player), 0) == 97) {
            _au_exec_aplay(path);
        } else {
            if (_au_byte(cast<char*>(player), 0) == 112) {
                _au_exec_paplay(path);
            } else {
                _au_exec_ffplay(path);
            }
        }
        sys_exit(127);
    }
    if (wait == 1) {
        int status = 0;
        sys_wait4(pid, &status, 0, null);
        return status / 256;
    }
    return pid;
}

fn audio_play_file(string path, int wait) -> int {
    int r = _au_try_player("aplay", path, wait);
    if (wait == 1) {
        if (r == 127) { r = _au_try_player("paplay", path, wait); }
    }
    if (wait == 1) {
        if (r == 127) { r = _au_try_player("ffplay", path, wait); }
    }
    return r;
}

fn audio_play_clip(AudioClip* c, int wait) -> int {
    if (c.valid == 0) { return -1; }
    string tmp = "/tmp/mg_audio_play.wav";
    if (audio_write_wav(tmp, c) == false) { return -1; }
    int r = audio_play_file(tmp, wait);
    if (wait == 1) { sys_unlink(tmp); }
    return r;
}

fn audio_play_wav(string path) -> int {
    return audio_play_file(path, 1);
}
