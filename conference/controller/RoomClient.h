//
//  RoomClient.h
//  conference
//
//  Created by houxh on 2023/6/1.
//  Copyright © 2023 beetle. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN


@class ARDCaptureController;
@class WebRTCVideoView;

@protocol VideoRendererDelegate <NSObject>

-(WebRTCVideoView*)createVideoView:(NSString*)id_ isLocal:(BOOL)isLocal;
-(void)removeVideoView:(NSString*)id_;

@end
@interface RoomClient : NSObject
@property(nonatomic, weak) id<VideoRendererDelegate> videoRendererDeleegate;
@property(nonatomic, assign) int64_t currentUID;
@property(nonatomic, copy) NSString *channelID;
@property(nonatomic, copy) NSString *token;

@property(nonatomic, assign) BOOL cameraOn;
@property(nonatomic, assign) BOOL microphoneOn;

@property(nonatomic, nullable) ARDCaptureController *captureController;


-(void)start;

-(void)stop;

-(void)produceVideo;
-(void)produceAudio;
-(void)closeAudioProducer;
-(void)closeVideoProducer;

@end

NS_ASSUME_NONNULL_END
