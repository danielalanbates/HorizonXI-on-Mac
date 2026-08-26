// audiofollow — make a running FFXI follow the Mac's sound-output setting.
//
// The problem
// -----------
// Wine's CoreAudio backend (winecoreaudio.drv, reached through mmdevapi/dsound) opens an AUHAL
// output unit and pins it to whichever device was the system default at the moment the game
// started its audio. macOS's "Sound Output" control changes the *default device*; it does not
// touch AudioUnits that already named a device. So switching from the laptop speakers to
// headphones mid-session moves every other app and leaves FFXI playing to the old device, with
// no way to fix it short of quitting the game.
//
// Apple's own fix for this is kAudioUnitSubType_DefaultOutput, which follows the default device
// on its own — but mmdevapi has to enumerate and name devices, so it uses HALOutput and cannot
// use it.
//
// The fix
// -------
// This dylib is inserted into the wine process (DYLD_INSERT_LIBRARIES). It:
//
//   1. interposes AudioComponentInstanceNew and remembers every output AudioUnit wine creates;
//   2. interposes AudioOutputUnitStart/Stop so it knows which of them are actually playing;
//   3. listens for kAudioHardwarePropertyDefaultOutputDevice on the system object;
//   4. when the default output changes, re-points each running unit at the new device
//      (stop -> set kAudioOutputUnitProperty_CurrentDevice -> start).
//
// Nothing here touches the game, wine, or any Square Enix data — it is entirely a CoreAudio-side
// correction, and if it fails to do anything the audio keeps playing exactly as it did before.
//
// Deliberately conservative:
//   * only units of type kAudioUnitType_Output are touched;
//   * a unit that was not started is re-pointed but not started;
//   * every CoreAudio call is checked, and a failure leaves the unit as it was and logs;
//   * the table is fixed-size and lock-protected — no allocation on the listener thread.
//
// Debug output: set FFXI_AUDIOFOLLOW_DEBUG=1 to get one stderr line per event.

#include <AudioToolbox/AudioToolbox.h>
#include <CoreAudio/CoreAudio.h>
#include <pthread.h>
#include <time.h>   // nanosleep, for the watchdog
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define AF_MAX_UNITS 32

struct af_unit {
    AudioUnit unit;      // NULL = free slot
    int running;         // AudioOutputUnitStart seen and not yet Stop'd
    int want_running;    // what the GAME asked for -- see af_retarget
};

static struct af_unit af_units[AF_MAX_UNITS];
static pthread_mutex_t af_lock = PTHREAD_MUTEX_INITIALIZER;
static int af_debug = 0;
static int af_listener_installed = 0;

static void af_log(const char *fmt, ...) {
    if (!af_debug) return;
    va_list ap;
    va_start(ap, fmt);
    fprintf(stderr, "audiofollow: ");
    vfprintf(stderr, fmt, ap);
    fprintf(stderr, "\n");
    va_end(ap);
}

static AudioDeviceID af_default_output(void) {
    AudioDeviceID dev = kAudioObjectUnknown;
    UInt32 size = sizeof(dev);
    AudioObjectPropertyAddress addr = {
        kAudioHardwarePropertyDefaultOutputDevice,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    OSStatus err = AudioObjectGetPropertyData(kAudioObjectSystemObject, &addr, 0, NULL, &size, &dev);
    if (err != noErr) {
        af_log("could not read the default output device (err %d)", (int)err);
        return kAudioObjectUnknown;
    }
    return dev;
}

/// Re-point one unit at `dev`. Returns 1 if the unit is now on `dev`.
static int af_retarget(struct af_unit *u, AudioDeviceID dev) {
    AudioDeviceID current = kAudioObjectUnknown;
    UInt32 size = sizeof(current);
    OSStatus err = AudioUnitGetProperty(u->unit, kAudioOutputUnitProperty_CurrentDevice,
                                        kAudioUnitScope_Global, 0, &current, &size);
    if (err == noErr && current == dev) return 1;   // already there, nothing to glitch

    int was_running = u->running;
    if (was_running) {
        err = AudioOutputUnitStop(u->unit);
        if (err != noErr) { af_log("stop failed (err %d) — leaving this unit alone", (int)err); return 0; }
    }

    err = AudioUnitSetProperty(u->unit, kAudioOutputUnitProperty_CurrentDevice,
                               kAudioUnitScope_Global, 0, &dev, sizeof(dev));
    if (err != noErr) {
        af_log("could not move a unit to device %u (err %d)", (unsigned)dev, (int)err);
        // Put it back the way we found it rather than leaving it stopped and silent.
        if (u->want_running) AudioOutputUnitStart(u->unit);
        return 0;
    }

    // Start whenever the GAME wants sound, not merely when the unit happened to be running a
    // moment ago.
    //
    // This is the bug that made FFXI go permanently silent when Jump Desktop was opened
    // (Daniel, 2026-08-25). Jump Desktop installs virtual audio devices that run at 192 kHz;
    // the default output flicks over them and back to the AirPods, and one of those moves can
    // fail to restart -- a sample-rate change mid-switch is enough. The old code then set
    // `running = 0`, and because every later retarget only restarted units that were running,
    // the unit was never started again. The default device was correct, the unit was pointed
    // at it, and nothing ever told it to play. One failure meant silence until the game was
    // restarted, which is exactly what it looked like from the outside.
    if (u->want_running) {
        err = AudioOutputUnitStart(u->unit);
        if (err != noErr) {
            af_log("moved a unit to device %u but could not start it (err %d) -- "
                   "it still wants to run, so the next device change will try again",
                   (unsigned)dev, (int)err);
            u->running = 0;
            return 0;
        }
        u->running = 1;
    }
    af_log("moved a unit to device %u", (unsigned)dev);
    return 1;
}

/// A slow re-assert, so a unit that ended up on the wrong device -- or stopped and never
/// restarted -- comes back on its own.
///
/// The property listener only fires when the default output *changes*. That is enough when
/// every move succeeds, but it means a single failure leaves the game silent until something
/// else happens to change the device, which in practice means until the game is restarted.
/// Opening Jump Desktop is exactly that case: its virtual devices appear, the default flicks
/// and settles back on the real one, and if the restart lost the race there is no second
/// event to recover on.
///
/// Three seconds is far slower than anything a person would notice as a glitch and costs one
/// property read per tick.
static void *af_watchdog(void *ctx) {
    (void)ctx;
    for (;;) {
        struct timespec ts = { .tv_sec = 3, .tv_nsec = 0 };
        nanosleep(&ts, NULL);

        AudioDeviceID dev = af_default_output();
        if (dev == kAudioObjectUnknown) continue;

        pthread_mutex_lock(&af_lock);
        for (int i = 0; i < AF_MAX_UNITS; i++) {
            struct af_unit *u = &af_units[i];
            if (!u->unit) continue;

            AudioDeviceID current = kAudioObjectUnknown;
            UInt32 size = sizeof(current);
            OSStatus err = AudioUnitGetProperty(u->unit, kAudioOutputUnitProperty_CurrentDevice,
                                                kAudioUnitScope_Global, 0, &current, &size);
            int wrong_device = (err == noErr && current != dev);
            int should_play  = (u->want_running && !u->running);
            if (wrong_device) {
                af_log("watchdog: a unit is on device %u but the default is %u",
                       (unsigned)current, (unsigned)dev);
                af_retarget(u, dev);
            } else if (should_play) {
                af_log("watchdog: a unit should be playing and is not; starting it");
                if (AudioOutputUnitStart(u->unit) == noErr) u->running = 1;
            }
        }
        pthread_mutex_unlock(&af_lock);
    }
    return NULL;
}

static OSStatus af_default_changed(AudioObjectID obj, UInt32 n,
                                   const AudioObjectPropertyAddress *addrs, void *ctx) {
    (void)obj; (void)n; (void)addrs; (void)ctx;
    AudioDeviceID dev = af_default_output();
    if (dev == kAudioObjectUnknown) return noErr;
    af_log("system output changed to device %u", (unsigned)dev);

    pthread_mutex_lock(&af_lock);
    for (int i = 0; i < AF_MAX_UNITS; i++)
        if (af_units[i].unit) af_retarget(&af_units[i], dev);
    pthread_mutex_unlock(&af_lock);
    return noErr;
}

/// Installed lazily — there is no point listening in a wine process that never plays a sound,
/// and there are a lot of those (wineboot, services.exe, the installer helpers).
static void af_install_listener_locked(void) {
    if (af_listener_installed) return;
    AudioObjectPropertyAddress addr = {
        kAudioHardwarePropertyDefaultOutputDevice,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    OSStatus err = AudioObjectAddPropertyListener(kAudioObjectSystemObject, &addr,
                                                  af_default_changed, NULL);
    if (err != noErr) { af_log("could not listen for output changes (err %d)", (int)err); return; }
    af_listener_installed = 1;
    af_log("listening for sound-output changes");

    // The listener alone cannot recover from a move that failed, because there is no second
    // event to recover on. See af_watchdog.
    pthread_t t;
    if (pthread_create(&t, NULL, af_watchdog, NULL) == 0) {
        pthread_detach(t);
        af_log("watchdog running");
    } else {
        af_log("could not start the watchdog; recovery is limited to device changes");
    }
}

static void af_track(AudioUnit unit) {
    pthread_mutex_lock(&af_lock);
    for (int i = 0; i < AF_MAX_UNITS; i++) {
        if (af_units[i].unit == NULL) {
            af_units[i].unit = unit;
            af_units[i].running = 0;
            af_units[i].want_running = 0;
            af_install_listener_locked();
            af_log("tracking output unit %d", i);
            break;
        }
    }
    pthread_mutex_unlock(&af_lock);
}

static void af_untrack(AudioUnit unit) {
    pthread_mutex_lock(&af_lock);
    for (int i = 0; i < AF_MAX_UNITS; i++)
        if (af_units[i].unit == unit) {
            af_units[i].unit = NULL; af_units[i].running = 0; af_units[i].want_running = 0;
        }
    pthread_mutex_unlock(&af_lock);
}

/// Record what the game asked for. `want_running` is the game's intent and survives a failed
/// restart; `running` is only what is true right now.
static void af_mark_running(AudioUnit unit, int running) {
    pthread_mutex_lock(&af_lock);
    for (int i = 0; i < AF_MAX_UNITS; i++)
        if (af_units[i].unit == unit) {
            af_units[i].running = running;
            af_units[i].want_running = running;
        }
    pthread_mutex_unlock(&af_lock);
}

// ---------------------------------------------------------------------------------------------
// Interposed entry points
// ---------------------------------------------------------------------------------------------

static OSStatus af_AudioComponentInstanceNew(AudioComponent comp, AudioComponentInstance *out) {
    OSStatus err = AudioComponentInstanceNew(comp, out);
    if (err == noErr && out && *out) {
        AudioComponentDescription desc;
        if (AudioComponentGetDescription(comp, &desc) == noErr &&
            desc.componentType == kAudioUnitType_Output) {
            af_track(*out);
        }
    }
    return err;
}

static OSStatus af_AudioComponentInstanceDispose(AudioComponentInstance inst) {
    af_untrack(inst);
    return AudioComponentInstanceDispose(inst);
}

static OSStatus af_AudioOutputUnitStart(AudioUnit unit) {
    OSStatus err = AudioOutputUnitStart(unit);
    if (err == noErr) af_mark_running(unit, 1);
    return err;
}

static OSStatus af_AudioOutputUnitStop(AudioUnit unit) {
    OSStatus err = AudioOutputUnitStop(unit);
    if (err == noErr) af_mark_running(unit, 0);
    return err;
}

__attribute__((constructor)) static void af_init(void) {
    const char *d = getenv("FFXI_AUDIOFOLLOW_DEBUG");
    af_debug = (d && *d && *d != '0');
    af_log("loaded");
}

#define AF_INTERPOSE(new, old) \
    __attribute__((used, section("__DATA,__interpose"))) \
    static const struct { const void *n; const void *o; } af_i_##old = { (const void *)&new, (const void *)&old };

AF_INTERPOSE(af_AudioComponentInstanceNew,     AudioComponentInstanceNew)
AF_INTERPOSE(af_AudioComponentInstanceDispose, AudioComponentInstanceDispose)
AF_INTERPOSE(af_AudioOutputUnitStart,          AudioOutputUnitStart)
AF_INTERPOSE(af_AudioOutputUnitStop,           AudioOutputUnitStop)
