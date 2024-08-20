//
//  ConferenceViewController.m
//  conference
//
//  Created by houxh on 2021/8/20.
//  Copyright © 2021 beetle. All rights reserved.
//

#import "ConferenceViewController.h"
#import <Masonry/Masonry.h>
#import <AVFAudio/AVFAudio.h>
#import <AVFoundation/AVFoundation.h>
#import <WebRTC/WebRTC.h>
#import <WebRTC/MSDevice.h>
#import <WebRTC/MSSendTransport.h>
#import <WebRTC/MSRecvTransport.h>
#import <WebRTC/MSClient.h>
#import <Protooclient/Protooclient.h>
#import "WebRTCVideoView.h"
#import "ARDCaptureController.h"

#import "RoomClient.h"


@interface VideoRenderer : NSObject
@property(nonatomic, copy) NSString *id_;
@property(nonatomic) WebRTCVideoView *videoView;
@end

@implementation VideoRenderer
-(instancetype)initWithId:(NSString*)id_ videoView:(WebRTCVideoView*)videoView {
    self = [super init];
    if (self) {
        self.id_ = id_;
        self.videoView = videoView;
    }
    return self;
}
@end


#define RGBCOLOR(r,g,b) [UIColor colorWithRed:(r)/255.0f green:(g)/255.0f blue:(b)/255.0f alpha:1]
#define kBtnWidth  72
#define kBtnHeight 72

#define kVideoViewWidth 160
#define kVideoViewHeight 160

@interface ConferenceViewController()<VideoRendererDelegate>
@property(nonatomic) NSMutableArray<VideoRenderer*> *renderers;


@property(nonatomic, weak) UILabel *durationLabel;
@property(nonatomic, weak) UIButton *cameraButton;
@property(nonatomic, weak) UIButton *muteButton;
@property(nonatomic, weak) UIButton *hangUpButton;
@property(nonatomic, weak) UIScrollView *scrollView;

@property(nonatomic) RoomClient *roomClient;
@end

@implementation ConferenceViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.renderers = [NSMutableArray array];
    
    [[UIApplication sharedApplication] setIdleTimerDisabled:YES];
    
    if (![self isHeadsetPluggedIn] && ![self isLoudSpeaker]) {
        NSError* error;
        [[AVAudioSession sharedInstance] overrideOutputAudioPort:AVAudioSessionPortOverrideSpeaker error:&error];
    }
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didSessionRouteChange:) name:AVAudioSessionRouteChangeNotification object:nil];
    
    UIScrollView *scrollView = [[UIScrollView alloc] init];
    self.scrollView = scrollView;
    [self.view addSubview:self.scrollView];
    
    [self.scrollView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.height.equalTo(self.view.mas_width);
        make.width.equalTo(self.view.mas_width);
        make.top.equalTo(self.view.mas_top).with.offset(60);
    }];
    
    UIButton *hangUpButton = [[UIButton alloc] init];
    self.hangUpButton = hangUpButton;
    [self.hangUpButton setBackgroundImage:[UIImage imageNamed:@"Call_hangup"] forState:UIControlStateNormal];
    [self.hangUpButton setBackgroundImage:[UIImage imageNamed:@"Call_hangup_p"] forState:UIControlStateHighlighted];
    [self.hangUpButton addTarget:self
                          action:@selector(hangUp:)
                forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.hangUpButton];
    
    [self.hangUpButton mas_makeConstraints:^(MASConstraintMaker *make) {
        make.centerX.equalTo(self.view.mas_centerX);
        make.size.mas_equalTo(CGSizeMake(kBtnWidth, kBtnHeight));
        make.bottom.equalTo(self.view.mas_bottom).with.offset(-80);
    }];
    
    UIButton *muteButton = [[UIButton alloc] init];
    self.muteButton = muteButton;
    [self.muteButton setImage:[UIImage imageNamed:@"unmute"] forState:UIControlStateNormal];
    [self.muteButton addTarget:self
                        action:@selector(onMute:)
              forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.muteButton];
    
    [self.muteButton mas_makeConstraints:^(MASConstraintMaker *make) {
        make.centerX.equalTo(self.view.mas_right).with.multipliedBy(0.25);
        make.size.mas_equalTo(CGSizeMake(42, 42));
        make.bottom.equalTo(self.view.mas_bottom).with.offset(-95);
    }];
    
    UIButton *cameraButton = [[UIButton alloc] init];
    self.cameraButton = cameraButton;
    [self.cameraButton setImage:[UIImage imageNamed:@"switch"] forState:UIControlStateNormal];
    [self.cameraButton addTarget:self
                          action:@selector(toggleCamera:)
                forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.cameraButton];
    
    [self.cameraButton mas_makeConstraints:^(MASConstraintMaker *make) {
        make.centerX.equalTo(self.view.mas_right).with.multipliedBy(0.75);
        make.size.mas_equalTo(CGSizeMake(42, 42));
        make.bottom.equalTo(self.view.mas_bottom).with.offset(-95);
    }];
    
    UILabel *durationLabel = [[UILabel alloc] init];
    self.durationLabel = durationLabel;
    [self.durationLabel setFont:[UIFont systemFontOfSize:23.0f]];
    [self.durationLabel setTextAlignment:NSTextAlignmentCenter];
    [self.durationLabel setText:@"000:000"];
    [self.durationLabel setTextColor:[UIColor whiteColor]];
    [self.durationLabel sizeToFit];
    [self.durationLabel setBackgroundColor:[UIColor clearColor]];
    [self.view addSubview:self.durationLabel];
    
    [self.durationLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.bottom.equalTo(self.hangUpButton.mas_top).with.offset(-20);
        make.centerX.equalTo(self.view.mas_centerX);
    }];
    
    self.roomClient = [[RoomClient alloc] init];
    self.roomClient.token = self.token;
    self.roomClient.currentUID = self.currentUID;
    self.roomClient.channelID = self.channelID;
    self.roomClient.videoRendererDeleegate = self;
    
    [self requestPermission];
}

- (void)requestPermission {
    AVAuthorizationStatus authStatus = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    AVAuthorizationStatus audioAuthStatus = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio];
    
    if (authStatus != AVAuthorizationStatusNotDetermined && audioAuthStatus != AVAuthorizationStatusNotDetermined) {
        //start event authorization denied
        [self.roomClient start];
    } else if (authStatus == AVAuthorizationStatusNotDetermined) {
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
            if(granted){
                AVAuthorizationStatus audioAuthStatus = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio];
                if (audioAuthStatus != AVAuthorizationStatusNotDetermined) {
                    [self.roomClient start];
                }
            } else {
                NSLog(@"Not granted access to %@", AVMediaTypeVideo);
            }
        }];
    } else {
        NSAssert(audioAuthStatus == AVAuthorizationStatusNotDetermined, @"");
        [[AVAudioSession sharedInstance] requestRecordPermission:^(BOOL granted) {
            if (granted) {
                AVAuthorizationStatus authStatus = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
                if (authStatus != AVAuthorizationStatusNotDetermined) {
                    [self.roomClient start];
                }
            } else {
                NSLog(@"Not granted access to %@", AVMediaTypeAudio);
            }
        }];
    }
}

-(WebRTCVideoView*)createVideoView:(NSString*)id_ isLocal:(BOOL)isLocal {
    //TODO localrender use RTCCameraPreviewView
    WebRTCVideoView *videoView = [[WebRTCVideoView alloc] initWithFrame:CGRectZero];
    
    videoView.objectFit = WebRTCVideoViewObjectFitCover;
    videoView.clipsToBounds = YES;
    
    if (isLocal) {
        UITapGestureRecognizer* singleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(switchCamera:)];
        [videoView addGestureRecognizer:singleTap];
    }
    
    CGFloat w = self.view.frame.size.width/2;
    CGFloat h = w;
    CGFloat y = h*(self.renderers.count/2);
    CGFloat x = w*(self.renderers.count%2);
    videoView.frame = CGRectMake(x, y, w, h);
    [self.scrollView addSubview:videoView];
    
    //    UIView *blackView = [[UIView alloc] init];
    //    blackView.backgroundColor = [UIColor blackColor];
    //    blackView.frame = CGRectMake(x, y, w, h);
    //    blackView.hidden = YES;
    //    [self.scrollView addSubview:blackView];
    
    NSInteger count = self.renderers.count;
    self.scrollView.contentSize = CGSizeMake(w*2, h*(count%2+count/2));
    
    VideoRenderer *r = [[VideoRenderer alloc] initWithId:id_ videoView:videoView];
    [self.renderers addObject:r];
    
    return videoView;
}

-(void)removeVideoView:(NSString*)id_ {
    NSUInteger index = [self.renderers indexOfObjectPassingTest:^BOOL(VideoRenderer * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        if ([obj.id_ isEqualToString:id_]) {
            *stop = TRUE;
            return TRUE;
        } else {
            return FALSE;
        }
    }];
    if (index == NSNotFound) {
        NSLog(@"Can't find renderer:%@", id_);
        return;
    }
    VideoRenderer *renderer = [self.renderers objectAtIndex:index];
    [self.renderers removeObjectAtIndex:index];
    [renderer.videoView removeFromSuperview];
    

    for (NSInteger i = 0; i < self.renderers.count; i++) {
        NSInteger viewIndex = i;
        VideoRenderer *renderer = [self.renderers objectAtIndex:i];
        CGFloat w = self.view.frame.size.width/2;
        CGFloat h = w;
        CGFloat y = h*(viewIndex/2);
        CGFloat x = w*(viewIndex%2);
        renderer.videoView.frame = CGRectMake(x, y, w, h);
    }
    
    CGFloat w = self.view.frame.size.width/2;
    CGFloat h = w;
    
    NSInteger count = self.renderers.count;
    self.scrollView.contentSize = CGSizeMake(w, h*(count%2+count/2));
}

-(void)switchCamera:(id)sender {
    NSLog(@"switch camera...");
    [self.roomClient.captureController switchCamera];
}


-(void)hangUp:(id)sender {
    [self.roomClient stop];
    [self dismissViewControllerAnimated:TRUE completion:nil];
}

-(void)onMute:(id)sender {
    self.roomClient.microphoneOn = !self.roomClient.microphoneOn;
    if (self.roomClient.microphoneOn) {
        [self.roomClient produceAudio];
        [self.muteButton setImage:[UIImage imageNamed:@"unmute"] forState:UIControlStateNormal];
    } else {
        [self.roomClient closeAudioProducer];
        [self.muteButton setImage:[UIImage imageNamed:@"mute"] forState:UIControlStateNormal];
    }
}

-(void)toggleCamera:(id)sender {
    self.roomClient.cameraOn = !self.roomClient.cameraOn;
    if (self.roomClient.cameraOn) {
        [self.roomClient produceVideo];
    } else {
        [self.roomClient closeVideoProducer];
    }
}


- (void)didSessionRouteChange:(NSNotification *)notification {
    NSDictionary *interuptionDict = notification.userInfo;
    NSInteger routeChangeReason = [[interuptionDict valueForKey:AVAudioSessionRouteChangeReasonKey] integerValue];
    NSLog(@"route change:%zd", routeChangeReason);
    if (![self isHeadsetPluggedIn] && ![self isLoudSpeaker]) {
        NSError* error;
        [[AVAudioSession sharedInstance] overrideOutputAudioPort:AVAudioSessionPortOverrideSpeaker error:&error];
    }
}


- (BOOL)isHeadsetPluggedIn {
    AVAudioSessionRouteDescription *route = [[AVAudioSession sharedInstance] currentRoute];
    
    BOOL headphonesLocated = NO;
    for( AVAudioSessionPortDescription *portDescription in route.outputs )
    {
        headphonesLocated |= ( [portDescription.portType isEqualToString:AVAudioSessionPortHeadphones] );
    }
    return headphonesLocated;
}


-(BOOL)isLoudSpeaker {
    AVAudioSession* session = [AVAudioSession sharedInstance];
    AVAudioSessionCategoryOptions options = session.categoryOptions;
    BOOL enabled = options & AVAudioSessionCategoryOptionDefaultToSpeaker;
    return enabled;
}
@end
