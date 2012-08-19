//
//  AudioPump.m
//  Sweep
//
//  Created by Robert Fielding on 8/5/12.
//  Copyright (c) 2012 Check Point Software. All rights reserved.
//

#import <AudioUnit/AUComponent.h>
#import <AudioUnit/AudioUnitProperties.h>
#import <AudioUnit/AudioOutputUnit.h>
#import <AudioToolbox/AudioServices.h>
#import <AudioToolbox/CAFFile.h>
#import <AVFoundation/AVFoundation.h>

#include "AudioPump.h"
#include "WaveEngine.h"


#define AUDIOCHANNELS 2

BOOL audioIsRunning = FALSE;
BOOL audioIsAudible = FALSE;
AudioComponentInstance audioUnit;
AudioStreamBasicDescription audioFormat;
static const float kSampleRate = 44100.0;
static const unsigned int kOutputBus = 0;


static void audioSessionInterruptionCallback(void *inUserData, UInt32 interruptionState) {
    if (interruptionState == kAudioSessionEndInterruption) {
        AudioSessionSetActive(YES);
        AudioOutputUnitStart(audioUnit);
    }
    
    if (interruptionState == kAudioSessionBeginInterruption) {
        AudioOutputUnitStop(audioUnit);
    }
}

static OSStatus fixGDLatency()
{
    //Prefer 256 samples @ 44.1khz.  Anything larger is difficult to play in the 
    //final instrument.
    float latency = 0.005;
    
    OSStatus
    status = AudioSessionSetProperty(
                                     kAudioSessionProperty_PreferredHardwareIOBufferDuration,
                                     sizeof(latency),&latency
                                     );
    if(status != 0)
    {
    }
    UInt32 allowMixing = true;
    status = AudioSessionSetProperty(
                                     kAudioSessionProperty_OverrideCategoryMixWithOthers,
                                     sizeof(allowMixing),&allowMixing
                                     );
    
    AudioStreamBasicDescription auFmt;
    UInt32 auFmtSize = sizeof(AudioStreamBasicDescription);
    
    AudioUnitGetProperty(audioUnit,
                         kAudioUnitProperty_StreamFormat,
                         kAudioUnitScope_Output,
                         kOutputBus,
                         &auFmt,
                         &auFmtSize);
    return status;
}



void SoundEngine_wake()
{
    NSLog(@"SoundEngine_wake()");
    NSError *categoryError = nil;
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:&categoryError];
    fixGDLatency();
    WE_init();
    audioIsRunning = TRUE;
    audioIsAudible = TRUE;
}


static OSStatus SoundEngine_playCallback(void *inRefCon,
                                         AudioUnitRenderActionFlags *ioActionFlags,
                                         const AudioTimeStamp *inTimeStamp,
                                         UInt32 inBusNumber,
                                         UInt32 inNumberFrames,
                                         AudioBufferList *ioData)
{
    assert(inBusNumber == kOutputBus);
    if(audioIsAudible)
    {
        AudioBuffer* outputBufferL = &ioData->mBuffers[0];
        SInt32* dataL = (SInt32*)outputBufferL->mData;
        AudioBuffer* outputBufferR = &ioData->mBuffers[1];
        SInt32* dataR = (SInt32*)outputBufferR->mData;
        WE_render(dataL,dataR,inNumberFrames);        
    }
    return 0;
}

void SoundEngine_start()
{
    // Initialize the audio session.
    AudioSessionInitialize(NULL, NULL, audioSessionInterruptionCallback, NULL);
    
    OSStatus status;
    // Describe audio component
    AudioComponentDescription desc;
    desc.componentType = kAudioUnitType_Output;
    desc.componentSubType = kAudioUnitSubType_RemoteIO;
    desc.componentFlags = 0;
    desc.componentFlagsMask = 0;
    desc.componentManufacturer = kAudioUnitManufacturer_Apple;
    
    // Get component
    AudioComponent outputComponent = AudioComponentFindNext(NULL, &desc);
    
    // Get audio units
    status = AudioComponentInstanceNew(outputComponent, &audioUnit);
    if(status)
    {
        NSLog(@"AudioComponentInstanceNew failed: %ld",status);
    }
    else
    {
        // Enable playback
        UInt32 enableIO = 1;
        status = AudioUnitSetProperty(audioUnit,
                                      kAudioOutputUnitProperty_EnableIO,
                                      kAudioUnitScope_Output,
                                      kOutputBus,
                                      &enableIO,
                                      sizeof(UInt32));
        if(status)
        {
            NSLog(@"AudioUnitSetProperty enable io failed: %ld",status);
        }
        else
        {
            audioFormat.mSampleRate = 44100.0;
            audioFormat.mFormatID = kAudioFormatLinearPCM;
            audioFormat.mFormatFlags = kAudioFormatFlagsAudioUnitCanonical;
            audioFormat.mBytesPerPacket = sizeof(AudioUnitSampleType);
            audioFormat.mFramesPerPacket = 1;
            audioFormat.mBytesPerFrame = sizeof(AudioUnitSampleType);
            audioFormat.mChannelsPerFrame = AUDIOCHANNELS;
            audioFormat.mBitsPerChannel = 8 * sizeof(AudioUnitSampleType);
            audioFormat.mReserved = 0;
            
            NSLog(@"%fhz %luchannel %lubit",audioFormat.mSampleRate,audioFormat.mChannelsPerFrame,audioFormat.mBitsPerChannel);
            // Apply format
            status = AudioUnitSetProperty(audioUnit,
                                          kAudioUnitProperty_StreamFormat,
                                          kAudioUnitScope_Input,
                                          kOutputBus,
                                          &audioFormat,
                                          sizeof(AudioStreamBasicDescription));
            if(status)
            {
                NSLog(@"AudioUnitSetProperty stream format failed: %ld",status);
            }
            else
            {
                UInt32 maxFrames = 1024*4;
                AudioUnitSetProperty(audioUnit,
                                     kAudioUnitProperty_MaximumFramesPerSlice,
                                     kAudioUnitScope_Input,
                                     kOutputBus,
                                     &maxFrames,
                                     sizeof(maxFrames));
                
                AURenderCallbackStruct callback;
                callback.inputProc = &SoundEngine_playCallback;
                
                // This is only required if you want the pointer to the object to be passed into the function.
                //callback.inputProcRefCon = self; ???? Is that required
                
                // Set output callback
                status = AudioUnitSetProperty(audioUnit,
                                              kAudioUnitProperty_SetRenderCallback,
                                              kAudioUnitScope_Global,
                                              kOutputBus,
                                              &callback,
                                              sizeof(AURenderCallbackStruct));
                if(status)
                {
                    NSLog(@"AudioUnitSetProperty render callback failed: %ld",status);
                }
                else
                {
                    status = AudioUnitInitialize(audioUnit);
                    if(status)
                    {
                        NSLog(@"AudioUnitSetProperty initialize failed: %ld",status);
                    }
                    else
                    {
                        status = AudioOutputUnitStart(audioUnit);
                        if(status)
                        {
                            NSLog(@"AudioUnitStart:%ld",status);
                        }
                        else
                        {
                            SoundEngine_wake();
                        }
                    }
                }
            }
        }
    }
}

void AP_start()
{
    if(audioIsAudible==FALSE)
    {
        audioIsAudible = TRUE;
        if(audioIsRunning == FALSE)
        {
            SoundEngine_start();
        }
        else 
        {
            AudioOutputUnitStart(audioUnit);
        }
        NSLog(@"rawEngineStart");        
    }
}

void AP_stop()
{
    AudioOutputUnitStop(audioUnit);   
    audioIsAudible = FALSE;
    NSLog(@"rawEngineStop");    
}
