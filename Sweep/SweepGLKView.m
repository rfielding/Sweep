//
//  SweepGLKView.m
//  Sweep
//
//  Created by Robert Fielding on 8/5/12.
//  Copyright (c) 2012 Check Point Software. All rights reserved.
//


#import "SweepGLKView.h"
#include "WaveEngine.h"
#include <stdio.h>

//Use TouchMapping to convert touch pointers into stable integer values from 0 to 15
#define FINGERMAX 16
#define NOBODY -1

static UITouch* utilFingerAlloced[FINGERMAX];

int TouchMapping_mapFinger(UITouch* ptr)
{
    //return an id if we already allocated one for this pointer
    for(int f=0; f<FINGERMAX; f++)
    {
        if(utilFingerAlloced[f] == ptr)
        {
            return f;
        }
    }
    //otherwise, map into a location and return that
    for(int f=0; f<FINGERMAX; f++)
    {
        if(utilFingerAlloced[f] == NULL)
        {
            //printf("TouchMapping_mapFinger %d -> %d\n",ptr, f);
            if((int)ptr == -1)
            {
                printf("unmapped something that doesn't look like a pointer: -1\n");
            }
            utilFingerAlloced[f] = ptr;
            return f;
        }
    }
    printf("TouchMapping_mapFinger ran out of slots!\n");
    return NOBODY;
}

void TouchMapping_unmapFinger(UITouch* ptr)
{
    for(int f=0; f<FINGERMAX; f++)
    {
        if(utilFingerAlloced[f] == ptr)
        {
            //printf("TouchMapping_unmapFinger %d !-> %d\n",ptr, f);
            utilFingerAlloced[f] = NULL;
            return;
        }
    }
    printf("TouchMapping_unmapFinger tried to unmap an unmapped pointer\n");
}


static float scaleFactor = 2;

@implementation SweepGLKView

- (int)guessScaleFactor
{
    UIScreen* screen = [UIScreen mainScreen];
    int w = screen.currentMode.size.width;
    int h = screen.currentMode.size.height;
    NSLog(@"dimensions: %d %d",w,h);
    if((w==640 && h==960) || (w==2048 && h==1536))
    {
        return 2;
    }
    else
    {
        return 1;
    }
}

- (id)initWithCoder:(NSCoder*)coder
{
    self = [super initWithCoder:coder];    
    NSLog(@"initializing SweepGLKView");
    scaleFactor = [self guessScaleFactor];
    [self setMultipleTouchEnabled:TRUE];
    return self;
}

- (id)initWithFrame:(CGRect)frame
{
    self.contentScaleFactor = scaleFactor;
    
    self = [super initWithFrame:frame];
    if (self) {
        // Initialization code
    }
    return self;
}

/*
// Only override drawRect: if you perform custom drawing.
// An empty implementation adversely affects performance during animation.
- (void)drawRect:(CGRect)rect
{
    // Drawing code
}
*/




- (void)handleTouchDown:(NSSet*)touches inPhase:(UITouchPhase)expectPhase
{
    UIScreen* screen = [UIScreen mainScreen];
    int wMax = screen.currentMode.size.width;
    int hMax = screen.currentMode.size.height;
    NSArray* touchArray = [touches allObjects];
    int touchCount = [touches count];
    for(int t=0; t < touchCount; t++)
    {
        UITouch* touch = [touchArray objectAtIndex:t];
        UITouchPhase phase = [touch phase];
        if(phase == expectPhase)
        {
            float x = [touch locationInView:self].x * scaleFactor; 
                //([touch locationInView:self].x * scaleFactor)/w;
            float y = [touch locationInView:self].y * scaleFactor;
                //1 - ([touch locationInView:self].y * scaleFactor)/h;
            
            float area = 1.0;
            id valFloat = [touch valueForKey:@"pathMajorRadius"];
            if(valFloat != nil)
            {
                area = ([valFloat floatValue]-4)/7.0;
            }
            WE_voice v  = TouchMapping_mapFinger(touch);
            WE_amp(v,1);
            WE_note(v, 72*(1-y/hMax));
            WE_timbre(v, 1, x/wMax);
            WE_timbre(v, 0, area);
        }
    }
    ////GenericTouchHandling_touchesFlush();
}

- (void)handleTouchUp:(NSSet*)touches inPhase:(UITouchPhase)expectPhase
{
    NSArray* touchArray = [touches allObjects];
    int touchCount = [touchArray count];
    for(int t=0; t < touchCount; t++)
    {
        UITouch* touch = [touchArray objectAtIndex:t];
        UITouchPhase phase = [touch phase];
        if(phase==expectPhase)
        {            
            WE_voice v  = TouchMapping_mapFinger(touch);
            WE_amp(v, 0);
            TouchMapping_unmapFinger(touch);    
        }
    }
    ////GenericTouchHandling_touchesFlush();
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event 
{
    [self handleTouchDown:touches inPhase:UITouchPhaseBegan];
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event 
{
    [self handleTouchDown:touches inPhase:UITouchPhaseMoved];
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event
{
    [self handleTouchUp:touches inPhase:UITouchPhaseEnded];
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event
{
    [self handleTouchUp:touches inPhase:UITouchPhaseEnded];
}



@end
