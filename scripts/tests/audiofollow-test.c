// Stand-in for wine's audio backend: creates an AUHAL output unit, pins it to the device that is
// default right now (exactly what winecoreaudio does), plays a quiet sine, and prints which
// device the unit is on once a second.
//
//   without audiofollow.dylib : the device id never changes when you switch Sound Output
//   with    audiofollow.dylib : it follows within a second
//
// Build/run: scripts/tests/audiofollow-test.sh
#include <AudioToolbox/AudioToolbox.h>
#include <CoreAudio/CoreAudio.h>
#include <math.h>
#include <stdio.h>
#include <unistd.h>

static double phase = 0;

static OSStatus render(void *ref, AudioUnitRenderActionFlags *flags, const AudioTimeStamp *ts,
                       UInt32 bus, UInt32 frames, AudioBufferList *io) {
    (void)ref; (void)flags; (void)ts; (void)bus;
    for (UInt32 b = 0; b < io->mNumberBuffers; b++) {
        float *out = (float *)io->mBuffers[b].mData;
        double p = phase;
        for (UInt32 i = 0; i < frames; i++) { out[i] = 0.03f * (float)sin(p); p += 2 * M_PI * 440.0 / 48000.0; }
    }
    phase += 2 * M_PI * 440.0 / 48000.0 * frames;
    return noErr;
}

static AudioDeviceID default_output(void) {
    AudioDeviceID dev = 0; UInt32 size = sizeof(dev);
    AudioObjectPropertyAddress a = { kAudioHardwarePropertyDefaultOutputDevice,
                                     kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain };
    AudioObjectGetPropertyData(kAudioObjectSystemObject, &a, 0, NULL, &size, &dev);
    return dev;
}

int main(int argc, char **argv) {
    int seconds = argc > 1 ? atoi(argv[1]) : 20;

    AudioComponentDescription desc = { kAudioUnitType_Output, kAudioUnitSubType_HALOutput,
                                       kAudioUnitManufacturer_Apple, 0, 0 };
    AudioComponent comp = AudioComponentFindNext(NULL, &desc);
    AudioUnit unit;
    if (AudioComponentInstanceNew(comp, &unit) != noErr) { puts("FAIL: no unit"); return 1; }

    // This is the line that causes the bug in wine: the device is named once, at open.
    AudioDeviceID dev = default_output();
    if (AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice,
                             kAudioUnitScope_Global, 0, &dev, sizeof(dev)) != noErr) {
        puts("FAIL: could not pin device"); return 1;
    }

    AudioStreamBasicDescription fmt = {0};
    fmt.mSampleRate = 48000; fmt.mFormatID = kAudioFormatLinearPCM;
    fmt.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved;
    fmt.mFramesPerPacket = 1; fmt.mChannelsPerFrame = 2; fmt.mBitsPerChannel = 32;
    fmt.mBytesPerFrame = 4; fmt.mBytesPerPacket = 4;
    AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &fmt, sizeof(fmt));

    AURenderCallbackStruct cb = { render, NULL };
    AudioUnitSetProperty(unit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &cb, sizeof(cb));

    if (AudioUnitInitialize(unit) != noErr) { puts("FAIL: init"); return 1; }
    if (AudioOutputUnitStart(unit) != noErr) { puts("FAIL: start"); return 1; }

    printf("unit pinned to device %u; system default is %u\n", (unsigned)dev, (unsigned)default_output());
    fflush(stdout);

    for (int i = 0; i < seconds; i++) {
        sleep(1);
        AudioDeviceID on = 0; UInt32 size = sizeof(on);
        AudioUnitGetProperty(unit, kAudioOutputUnitProperty_CurrentDevice,
                             kAudioUnitScope_Global, 0, &on, &size);
        AudioDeviceID sys = default_output();
        printf("t=%2ds  unit=%u  system=%u  %s\n", i + 1, (unsigned)on, (unsigned)sys,
               on == sys ? "FOLLOWING" : "STUCK");
        fflush(stdout);
    }
    AudioOutputUnitStop(unit);
    AudioComponentInstanceDispose(unit);
    return 0;
}
