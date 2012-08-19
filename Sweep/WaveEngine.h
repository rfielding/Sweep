//
//  WaveEngine.h
//  Sweep
//
//  Created by Robert Fielding on 8/5/12.
//  Copyright (c) 2012 Check Point Software. All rights reserved.
//

///
///Protocol:
///
///  WE_init -> [ WE_note(v) | WE_amp(v) | WE_timbre(v,p) | WE_render ]+
///
///The control protocol is simply per-voice updates to freq,amp,timbre[p],
///and calls to periodically render the waves into a given buffer
///

#ifndef Sweep_WaveEngine_h
#define Sweep_WaveEngine_h


typedef int WE_voice;
typedef int WE_parm;


//Initialize state of engine
void WE_init();

//Set frequency to move voice to on next render
// val should be a floating point midi number 0..127
void WE_note(WE_voice v, float val);

//Set amplitude to move voice to on next render
//Use amplitude to turn voices on and off.  val should be 0..1
void WE_amp(WE_voice v, float val);

//Set timbre parameter for voice to move to on next render
//0 and 1 are valid parm values for now.  val should be 0..1
void WE_timbre(WE_voice v, WE_parm parm, float val);

//Render the current buffer
void WE_render(long left[], long right[], long samples);

#endif
