//
//  MPIInputStreamChannel.m
//  Multipeer.Instrument
//
//  Created by Kyle Beyer on 7/2/14.
//  Copyright (c) 2014 Kyle Beyer. All rights reserved.
//

#import "MPIInputStreamChannel.h"
#import "TPCircularBuffer.h"
#import "TPCircularBuffer+AudioBufferList.h"
#import "AEAudioController+Audiobus.h"
#import "AEAudioController+AudiobusStub.h"

#import "TDAudioInputStreamer.h"

static const int kAudioBufferLength = 16384;

@interface MPIInputStreamChannel () {
    TPCircularBuffer _buffer;
    
    //AudioBuffer _audioBuffer;
    
    TDAudioInputStreamer* _streamer;
    BOOL _audiobusConnectedToSelf;
}
@property (nonatomic, strong) AEAudioController *audioController;
@end

@implementation MPIInputStreamChannel
@synthesize audioController=_audioController, volume = _volume;

+(NSSet *)keyPathsForValuesAffectingAudioDescription {
    return [NSSet setWithObject:@"audioController.inputAudioDescription"];
}

- (id)initWithAudioController:(AEAudioController*)audioController stream:(NSInputStream*)stream {
    if ( !(self = [super init]) ) return nil;
    
    TPCircularBufferInit(&_buffer, kAudioBufferLength);
    self.audioController = audioController;
    _volume = 1.0;
    
    
    //_inputStream = stream;
    _streamer = [[TDAudioInputStreamer alloc] initWithInputStream:stream audioController:audioController streamChannel:self];
    return self;
}

- (void)dealloc {
    TPCircularBufferCleanup(&_buffer);
    self.audioController = nil;
    [self stop];
}

- (void)parseData:(const void *)data length:(UInt32)length
{
    UInt32 inFrames = 512;
    
    AudioBuffer inBuffer;
    /*
     we set the number of channels to mono and allocate our block size to
     1024 bytes.
     */
    inBuffer.mNumberChannels = 1;
    inBuffer.mDataByteSize = inFrames * 2;
    inBuffer.mData = malloc( inFrames * 2 );
    
    AudioBufferList bufferList;
    bufferList.mNumberBuffers = 2;
    // copy to both buffers so that it plays in left&right speaker
    bufferList.mBuffers[0] = inBuffer;
    bufferList.mBuffers[1] = inBuffer;
    
    // copy incoming audio data to the audio buffer
    memcpy(bufferList.mBuffers[0].mData, data, length);
    
    // AMPLIFY
    int gain = 4;
    
    /**
     Here we modify the raw data buffer now.
     In my example this is a simple input volume gain.
     iOS 5 has this on board now, but as example quite good.
     */
    SInt16 *editBuffer = bufferList.mBuffers[0].mData;
    
    // loop over every packet
    for (int nb = 0; nb < (inBuffer.mDataByteSize / 2); nb++) {
        
        // we check if the gain has been modified to save resoures
        if (gain != 0) {
            // we need more accuracy in our calculation so we calculate with doubles
            double gainSample = ((double)editBuffer[nb]) / 32767.0;
            
            /*
             at this point we multiply with our gain factor
             we dont make a addition to prevent generation of sound where no sound is.
             
             no noise
             0*10=0
             
             noise if zero
             0+10=10
             */
            gainSample *= gain;
            
            /**
             our signal range cant be higher or lesser -1.0/1.0
             we prevent that the signal got outside our range
             */
            gainSample = (gainSample < -1.0) ? -1.0 : (gainSample > 1.0) ? 1.0 : gainSample;
            
            /*
             This thing here is a little helper to shape our incoming wave.
             The sound gets pretty warm and better and the noise is reduced a lot.
             Feel free to outcomment this line and here again.
             
             You can see here what happens here http://silentmatt.com/javascript-function-plotter/
             Copy this to the command line and hit enter: plot y=(1.5*x)-0.5*x*x*x
             */
            
            gainSample = (1.5 * gainSample) - 0.5 * gainSample * gainSample * gainSample;
            
            // multiply the new signal back to short
            gainSample = gainSample * 32767.0;
            
            // write calculate sample back to the buffer
            editBuffer[nb] = (SInt16)gainSample;
        }
    }
    
    
    AudioStreamBasicDescription audioDesc = [self audioDescription];
    TPCircularBufferCopyAudioBufferList(&_buffer, &bufferList, NULL, inFrames, &audioDesc);
    
    // free up temporary audio buffer after copy
    free(bufferList.mBuffers[0].mData);
}

static OSStatus renderCallback(__unsafe_unretained MPIInputStreamChannel *THIS,
                               __unsafe_unretained AEAudioController *audioController,
                               const AudioTimeStamp     *time,
                               UInt32                    frames,
                               AudioBufferList          *audio) {
    

    while ( 1 ) {
        // Discard any buffers with an incompatible format, in the event of a format change
        AudioBufferList *nextBuffer = TPCircularBufferNextBufferList(&THIS->_buffer, NULL);
        if ( !nextBuffer ) break;
        if ( nextBuffer->mNumberBuffers == audio->mNumberBuffers ) break;
        TPCircularBufferConsumeNextBufferList(&THIS->_buffer);
    }
    
    UInt32 fillCount = TPCircularBufferPeek(&THIS->_buffer, NULL, AEAudioControllerAudioDescription(audioController));
    if ( fillCount > frames ) {
        UInt32 skip = fillCount - frames;
        TPCircularBufferDequeueBufferListFrames(&THIS->_buffer,
                                                &skip,
                                                NULL,
                                                NULL,
                                                AEAudioControllerAudioDescription(audioController));
        
        NSLog(@"fillCount (%i) > frames (%i)", fillCount, frames);
    }
    
    TPCircularBufferDequeueBufferListFrames(&THIS->_buffer,
                                            &frames,
                                            audio,
                                            NULL,
                                            AEAudioControllerAudioDescription(audioController));

    
    return noErr;
}

-(AEAudioControllerRenderCallback)renderCallback {
    return renderCallback;
}

-(AudioStreamBasicDescription)audioDescription {
    return _audioController.inputAudioDescription;
}



- (void)start
{
    [_streamer start];
}
- (void)stop
{
    [_streamer stop];
}


@end


