// Non-blocking PC Speaker audio for UEFI
// Uses a note queue that gets processed each frame

const std = @import("std");

// Note definitions (frequencies in Hz)
pub const NOTE_REST = 0;
pub const NOTE_C2 = 65;
pub const NOTE_CS2 = 69;
pub const NOTE_D2 = 73;
pub const NOTE_DS2 = 78;
pub const NOTE_E2 = 82;
pub const NOTE_F2 = 87;
pub const NOTE_FS2 = 92;
pub const NOTE_G2 = 98;
pub const NOTE_GS2 = 104;
pub const NOTE_A2 = 110;
pub const NOTE_AS2 = 116;
pub const NOTE_B2 = 123;
pub const NOTE_C3 = 131;
pub const NOTE_CS3 = 139;
pub const NOTE_D3 = 147;
pub const NOTE_DS3 = 156;
pub const NOTE_E3 = 165;
pub const NOTE_F3 = 175;
pub const NOTE_FS3 = 185;
pub const NOTE_G3 = 196;
pub const NOTE_GS3 = 208;
pub const NOTE_A3 = 220;
pub const NOTE_AS3 = 233;
pub const NOTE_B3 = 247;
pub const NOTE_C4 = 262;
pub const NOTE_CS4 = 277;
pub const NOTE_D4 = 294;
pub const NOTE_DS4 = 311;
pub const NOTE_E4 = 330;
pub const NOTE_F4 = 349;
pub const NOTE_FS4 = 370;
pub const NOTE_G4 = 392;
pub const NOTE_GS4 = 415;
pub const NOTE_A4 = 440;
pub const NOTE_AS4 = 466;
pub const NOTE_B4 = 494;
pub const NOTE_C5 = 523;
pub const NOTE_CS5 = 554;
pub const NOTE_D5 = 587;
pub const NOTE_DS5 = 622;
pub const NOTE_E5 = 659;
pub const NOTE_F5 = 698;
pub const NOTE_FS5 = 740;
pub const NOTE_G5 = 784;
pub const NOTE_GS5 = 831;
pub const NOTE_A5 = 880;
pub const NOTE_AS5 = 932;
pub const NOTE_B5 = 988;
pub const NOTE_C6 = 1047;
pub const NOTE_CS6 = 1109;
pub const NOTE_D6 = 1175;
pub const NOTE_DS6 = 1245;
pub const NOTE_E6 = 1319;
pub const NOTE_F6 = 1397;
pub const NOTE_FS6 = 1480;
pub const NOTE_G6 = 1568;
pub const NOTE_GS6 = 1661;
pub const NOTE_A6 = 1760;
pub const NOTE_AS6 = 1865;
pub const NOTE_B6 = 1976;
pub const NOTE_C7 = 2093;
pub const NOTE_CS7 = 2217;
pub const NOTE_D7 = 2349;

// Note structure
pub const Note = struct {
    freq: u32, // Frequency in Hz (0 = rest)
    duration: u32, // Duration in frames (at 60fps: 60 = 1 second)
};

// Audio player state
pub const AudioPlayer = struct {
    notes: [256]Note = undefined, // Note queue
    num_notes: u32 = 0, // Number of notes in queue
    current_note: u32 = 0, // Current note index
    frame_counter: u32 = 0, // Frames elapsed in current note
    is_playing: bool = false,

    // Initialize player
    pub fn init(self: *AudioPlayer) void {
        self.num_notes = 0;
        self.current_note = 0;
        self.frame_counter = 0;
        self.is_playing = false;
    }

    // Clear queue
    pub fn clear(self: *AudioPlayer) void {
        self.stop();
        self.num_notes = 0;
        self.current_note = 0;
        self.frame_counter = 0;
    }

    // Add note to queue
    pub fn addNote(self: *AudioPlayer, freq: u32, duration_frames: u32) void {
        if (self.num_notes >= self.notes.len) return;
        self.notes[self.num_notes] = .{ .freq = freq, .duration = duration_frames };
        self.num_notes += 1;
    }

    // Start playing
    pub fn play(self: *AudioPlayer) void {
        if (self.num_notes > 0) {
            self.is_playing = true;
            self.current_note = 0;
            self.frame_counter = 0;
            // Start first note
            playTone(self.notes[0].freq);
        }
    }

    // Stop playing
    pub fn stop(self: *AudioPlayer) void {
        self.is_playing = false;
        stopTone();
    }

    // Update called every frame (60fps assumed)
    pub fn update(self: *AudioPlayer) void {
        if (!self.is_playing) return;
        if (self.current_note >= self.num_notes) {
            // Finished all notes
            self.stop();
            return;
        }

        const note = self.notes[self.current_note];
        self.frame_counter += 1;

        if (self.frame_counter >= note.duration) {
            // Move to next note
            self.current_note += 1;
            self.frame_counter = 0;

            if (self.current_note < self.num_notes) {
                // Start next note
                playTone(self.notes[self.current_note].freq);
            } else {
                // Finished
                self.stop();
            }
        }
    }
};

// Global audio player
pub var audio_player: AudioPlayer = .{};

// PC Speaker hardware functions (inline for speed)
inline fn playTone(frequency: u32) void {
    if (frequency == 0) {
        stopTone();
        return;
    }

    // Calculate PIT divisor (1193180 Hz is the base PIT frequency)
    const divisor: u16 = @intCast(1193180 / frequency);

    // Tell PIT we're setting channel 2 (speaker)
    asm volatile ("outb %[cmd], $0x43"
        :
        : [cmd] "{al}" (@as(u8, 0xB6)),
    );

    // Send low byte of divisor
    asm volatile ("outb %[lo], $0x42"
        :
        : [lo] "{al}" (@as(u8, @truncate(divisor))),
    );

    // Send high byte of divisor
    asm volatile ("outb %[hi], $0x42"
        :
        : [hi] "{al}" (@as(u8, @intCast(divisor >> 8))),
    );

    // Enable speaker
    var tmp: u8 = 0;
    asm volatile ("inb $0x61, %[result]"
        : [result] "={al}" (tmp),
    );
    asm volatile ("outb %[val], $0x61"
        :
        : [val] "{al}" (@as(u8, tmp | 3)),
    );
}

inline fn stopTone() void {
    var tmp: u8 = 0;
    asm volatile ("inb $0x61, %[result]"
        : [result] "={al}" (tmp),
    );
    asm volatile ("outb %[val], $0x61"
        :
        : [val] "{al}" (@as(u8, tmp & 0xFC)),
    );
}

// Play a single note immediately (replaces current playback)
pub fn playNote(freq: u32, duration_frames: u32) void {
    audio_player.clear();
    audio_player.addNote(freq, duration_frames);
    audio_player.play();
}

// Sound effect presets
pub fn sfxClick() void {
    playNote(NOTE_C5, 2); // Short high beep
}

pub fn sfxPlaceTile() void {
    audio_player.clear();
    audio_player.addNote(NOTE_E4, 3);
    audio_player.play();
}

pub fn sfxRegenerate() void {
    audio_player.clear();
    audio_player.addNote(NOTE_C3, 4);
    audio_player.addNote(NOTE_E3, 4);
    audio_player.addNote(NOTE_G3, 6);
    audio_player.play();
}

pub fn sfxError() void {
    audio_player.clear();
    audio_player.addNote(NOTE_A3, 6);
    audio_player.addNote(NOTE_REST, 2);
    audio_player.addNote(NOTE_A3, 6);
    audio_player.play();
}
