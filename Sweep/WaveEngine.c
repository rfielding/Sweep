//
//  WaveEngine.c
//  Sweep
//
//  Created by Robert Fielding on 8/5/12.
//  Copyright (c) 2012 Check Point Software. All rights reserved.
//

#include <stdio.h>
#include <stdlib.h>

#include "WaveEngine.h"
#include <math.h>

//We want 256, but we expect buffer size to jump around.
//Specifically, it will jump to 1024 at times, and when sleeping
//it can go as high as 4096 as far as I have seen.
#define MAX_AUDIOBUFFER 4096

#define WE_TABLEBITS 8
#define WE_TABLESIZE (1<<WE_TABLEBITS)
#define WE_TABLEMASK (WE_TABLESIZE-1)
#define WE_VOICES 16
#define WE_PARMS 4
#define WE_FBITS 2
#define WE_F (1<<WE_FBITS)
#define WE_FMASK (WE_F-1)
#define WE_CYCLEBITS 8
#define WE_CYCLES (1<<WE_CYCLEBITS)
#define WE_CYCLEMASK (WE_CYCLES-1)

//Over-exercise the engine with one too many choruses so
//that performance doesn't get out of hand when we go back down to what we want.
#define WE_CHORUS 4

#define N WE_TABLESIZE
#define C WE_CYCLES
#define V WE_VOICES
#define P WE_PARMS

////BEGIN WE_audioMipMap
//
/*
   The whole point of this little project is experimenting with a Mipmap style
   audio sample.  Since you can never truly filter out digital aliasing once it 
   is introduced, this lets you put in samples per octave (or simply have one 
   sample be filtered of aliasing frequencies).  If you build samples as a sum
   of sine waves, without exceeding the nyquist limit, then aliasing cannot happen.
 
   The other thing is that it supports having a sequence of cycles (ie: not single
   cycle wave).  This can merely be a set that we can wander through, or it can 
   be a full arbitrary cycle that has been cut up into pieces.
 
   Then finally, there is a set of these sample buffers that we can fade between.
   This should let us completely separate playback speed from frequency, at the cost
   of possibly adding a sort of ring modulation effect to the original sample if 
   it doesn't really have a clear fundamental frequency of its own.
 */
//


#define P_NOTE 0
#define P_AMP  1
#define P_T0   2
#define P_T1   3

struct WE_parm {
    float rate;
    float now;
    float interp;
    float next;
};

struct WE_voices {
    //State of the voice, in radians
    float phase[WE_CHORUS];
    
    //These are used to handle parameter changes
    struct WE_parm parm[P];
};

struct WE_engine {
    struct WE_voices voice[V];
    //Two mipmaps to fade between, possibly not packed together
    float table[C][2][N*2]; 
    long  sample;
    float tableStart[WE_TABLEBITS];
} WE_state;

//Pick a sample at the correct octave, whee sample buffer is packed
//with half-size octave higher rendering appended to each buffer.
static inline float sample(const float w[N*2],int s, int oct)
{
    int is = (N - N>>oct)<<1;
    int id = (s&WE_TABLEMASK)>>oct;
    return w[is + id];
}

//Linear interpolate the sample value w[s] with the next value up
static inline float lisample(const float w[N*2],float s,int oct)
{
    float s0 = sample(w,(int)s,oct);
    float s1 = sample(w,1+(int)s,oct);
    float ds  = (s - (int)s);
    return s0 + (s1 - s0) * ds;
}

//Octave interpolation of the linear interpolated sample
static inline float olisample(const float w[N*2],float s,float oct)
{
    float s0 = lisample(w,s,(int)oct);
    float s1 = lisample(w,s,1+(int)oct);
    float ds  = (oct - (int)oct);
    return s0 + (s1 - s0) * ds;
}

//Cross-fade between two Octave/Linear interpolated samples
static inline float folisample(float f,const float w0[N*2],const float w1[N*2],float s,float oct)
{
    float s0 = olisample(w0,s,oct);
    float s1 = olisample(w1,s,oct);
    float ds  = (f - (int)f);
    return s0 + (s1 - s0) * ds;
}
                
//Interpolate across an array of cross-faded samples
static inline float pfolisample(float f0,float f1,float wt[C][2][N*2], float s,float oct)
{
    int wt1  = ((int)f1)&WE_CYCLEMASK;
    int wt1h = (1+(int)f1)&WE_CYCLEMASK;
    int ft   = ((int)f0)&WE_FMASK;
    int fth  = (1+(int)f0)&WE_FMASK;
    float s0 = folisample(f0,wt[wt1 ][ft],wt[wt1] [fth],s,oct);
    float s1 = folisample(f0,wt[wt1h][ft],wt[wt1h][fth],s,oct);
    float ds  = (f1 - (int)f1);
    return s0 + (s1 - s0) * ds;
}


////END WE_audioMipMap



void WE_init() 
{
    printf("WE_init");
    WE_state.sample = 0;
    //Fill tables with noise
    for(int c=0; c<C; c++)
    {
        int sz = WE_TABLESIZE;
        int start = 0;
        for(int n=0; n<WE_TABLEBITS; n++)
        {
            WE_state.tableStart[n] = 2*(N - N>>n);
            for(int i=0; i<sz; i++)
            {
                ////TODO: write wave tables
                double phase = (i * 2.0 * M_PI) / (1.0 * N);
                WE_state.table[c][0][start+i] = (1.0*rand())/RAND_MAX; 
                WE_state.table[c][1][start+i] = sinf(phase);                    
                WE_state.table[c][2][start+i] = sinf(2*phase);                    
                WE_state.table[c][3][start+i] = sinf(4*phase);                    
            }                    
            start += sz;
            sz = sz>>1;
        }
    }
    for(WE_voice v=0; v<V; v++)
    {
        for(int c=0; c<WE_CHORUS; c++)
        {
            WE_state.voice[v].phase[c]   = 0;            
        }
        for(WE_parm p=0; p<P; p++)
        {
            WE_state.voice[v].parm[p].now = 0;
            WE_state.voice[v].parm[p].next = 0; 
            WE_state.voice[v].parm[p].interp = 0;
            WE_state.voice[v].parm[p].rate   = 0.5;
        }
    }
}

void WE_amp(WE_voice v,float val)
{
    WE_state.voice[v].parm[P_AMP].next = val;
}

void WE_note(WE_voice v,float val)
{   
    WE_state.voice[v].parm[P_NOTE].next = val;
}

void WE_timbre(WE_voice v, WE_parm p, float val)
{
    WE_state.voice[v].parm[p+2].next = val;
}

static inline void interp_voice(int v)
{
    for(int p=0; p<P; p++)
    {
        float r = WE_state.voice[v].parm[p].rate;
        WE_state.voice[v].parm[p].interp =
               r  * WE_state.voice[v].parm[p].now +
            (1-r) * WE_state.voice[v].parm[p].next;
    }    
}

static inline void commit_voice(int v)
{
    for(int p=0; p<P; p++)
    {
        WE_state.voice[v].parm[p].now = WE_state.voice[v].parm[p].interp;            
    }    
}

void WE_render(long left[], long right[], long samples) 
{
    static float leftf[MAX_AUDIOBUFFER];
    static float rightf[MAX_AUDIOBUFFER];
    
    //Pre-render work
    for(int i=0;i<samples;i++)
    {
        leftf[i]  = 0;
        rightf[i] = 0;
    }
    
    //Rendering
    float invSamples = 1.0/samples;
    for(WE_voice v=0; v<V; v++)
    {
        interp_voice(v);
        float aOld  = WE_state.voice[v].parm[P_AMP].now;
        float a     = WE_state.voice[v].parm[P_AMP].next;
        float aI    = WE_state.voice[v].parm[P_AMP].interp;
        float aDiff = aI - aOld;
        if(a > 0 || aOld > 0 || aI > 0)
        {
            float nI         = WE_state.voice[v].parm[P_NOTE].interp;
            float t0I        = WE_state.voice[v].parm[P_T0].interp;
            float t1I        = WE_state.voice[v].parm[P_T1].interp;
            float o      = nI/12;
            for(int c=0;c<WE_CHORUS;c++)
            {
                //Not sure if double precision helps here.  I am assuming
                float p     = WE_state.voice[v].phase[c];
                float cyclesPerSample = powf(2,(nI+c*0.1-33)/12) * (440/(44100.0*32));
                for(int i=0;i<samples;i++)
                {
                    float phase = p + (cyclesPerSample*i);
                    float s = pfolisample(t1I,phase*0.01,WE_state.table, phase * N,o);
                    float aInterp = aOld + (aDiff*i)*invSamples;
                    leftf[i]  += (s * aInterp * t0I)*0.6;
                    rightf[i] = leftf[i];
                }                        
                WE_state.voice[v].phase[c] = p + (cyclesPerSample*(samples));            
            }
        }
        else 
        {
            for(int c=0;c<WE_CHORUS;c++)
            {
                WE_state.voice[v].phase[c] = 0;
            }
        }
        commit_voice(v);
    }
    //Post-render composting
    for(int i=0; i<samples; i++)
    {
        left[i]  = (long)(leftf[i] * 0x7fffff);
        right[i] = left[i]; 
    }
    
    WE_state.sample += samples;
}