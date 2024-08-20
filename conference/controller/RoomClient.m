//
//  RoomClient.m
//  conference
//
//  Created by houxh on 2023/6/1.
//  Copyright © 2023 beetle. All rights reserved.
//

#import "RoomClient.h"
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

static NSString * const kARDAudioTrackId = @"ARDAMSa0";
static NSString * const kARDVideoTrackId = @"ARDAMSv0";

@interface Producer : NSObject
@property(nonatomic, copy) NSString *id_;
@property(nonatomic, copy) NSString *localId;
@property(nonatomic) RTCRtpSender *rtpSender;
@property(nonatomic) RTCMediaStreamTrack *track;
@property(nonatomic) NSDictionary *rtpParameters;

@end

@implementation Producer

@end

@interface Consumer: NSObject
@property(nonatomic, copy) NSString *id_;
@property(nonatomic, copy) NSString *localId;
@property(nonatomic, copy) NSString *producerId;
@property(nonatomic) RTCRtpReceiver *rtpReceiver;
@property(nonatomic) RTCMediaStreamTrack *track;
@property(nonatomic) NSDictionary *rtpParameters;
@property(nonatomic, copy) NSString *peerId;
@end

@implementation Consumer


@end


@interface PendingRequest : NSObject
@property(nonatomic) ProtooclientRequest *request;
@property(nonatomic) void(^onSuccess)(ProtooclientResponse *r) ;
@property(nonatomic) void(^onError)(ProtooclientResponse *r);

-(instancetype)initWithRequest:(ProtooclientRequest*)req onSuccess:(void (^)(ProtooclientResponse*))onSuccess onError:(void (^)(ProtooclientResponse*))onError;
@end

@implementation PendingRequest

-(instancetype)initWithRequest:(ProtooclientRequest*)req onSuccess:(void (^)(ProtooclientResponse*))onSuccess onError:(void (^)(ProtooclientResponse*))onError {
    self = [super init];
    if (self) {
        self.request = req;
        self.onSuccess = onSuccess;
        self.onError = onError;
    }
    return self;
}

@end


@interface RoomClient ()<ProtooclientPeerListener>
@property(nonatomic) RTCConfiguration *rtcConfiguration;
@property(nonatomic) RTCPeerConnectionFactory *factory;
@property(nonatomic) NSMutableDictionary<NSNumber*, PendingRequest*> *pendingRequests;
@property(nonatomic) MSDevice *device;
@property(nonatomic) MSSendTransport *sendTransport;
@property(nonatomic) MSRecvTransport *recvTransport;


@property(nonatomic) RTCVideoSource *videoSource;
@property(nonatomic) RTCVideoTrack *localVideoTrack;
@property(nonatomic) RTCAudioTrack *localAudioTrack;
@property(nonatomic) RTCAudioSource *audioSource;

@property(nonatomic) Producer *videoProducer;
@property(nonatomic) Producer *audioProducer;
@property(nonatomic) NSMutableDictionary *consumers;

@property(nonatomic) ProtooclientPeer *peerClient;
@property(nonatomic) int nextId;
@end

@implementation RoomClient

- (instancetype)init {
    self = [super init];
    if (self) {
        
        //cause [MSClient initialize] be called
        NSLog(@"mediasoup client version:%@", [MSClient version]);

        self.microphoneOn = TRUE;
        self.cameraOn = TRUE;
        
        self.consumers = [NSMutableDictionary dictionary];
        self.pendingRequests = [NSMutableDictionary dictionary];
        RTCConfiguration *config = [[RTCConfiguration alloc] init];
        config.tcpCandidatePolicy = RTCTcpCandidatePolicyDisabled;
        config.bundlePolicy = RTCBundlePolicyMaxBundle;
        config.rtcpMuxPolicy = RTCRtcpMuxPolicyRequire;
        config.continualGatheringPolicy = RTCContinualGatheringPolicyGatherContinually;
        config.keyType = RTCEncryptionKeyTypeECDSA;
        config.sdpSemantics = RTCSdpSemanticsUnifiedPlan;
        self.rtcConfiguration = config;
        RTCDefaultVideoDecoderFactory *decoderFactory = [[RTCDefaultVideoDecoderFactory alloc] init];
        RTCDefaultVideoEncoderFactory *encoderFactory = [[RTCDefaultVideoEncoderFactory alloc] init];
        [RTCDefaultVideoEncoderFactory supportedCodecs];
        self.factory = [[RTCPeerConnectionFactory alloc] initWithEncoderFactory:encoderFactory
                                                                 decoderFactory:decoderFactory];
    }
    return self;
}


-(void)start {
    // be careful! golang code can't trigger network access to the system and get error:"no route to host".
    NSString *url = [NSString stringWithFormat:@"ws://192.168.1.101:4444/?peerId=%lld&roomId=%@&mode=group", self.currentUID, self.channelID];
    self.peerClient = [[ProtooclientPeer alloc] init:url listener:self];
    [self.peerClient open];
}

-(void)stop {
    [self.peerClient close];
    [self.captureController stopCapture];
    [self.sendTransport close];
    [self.recvTransport close];
    self.captureController = nil;
    self.localVideoTrack = nil;
    self.videoSource = nil;
    self.videoProducer = nil;
    self.localAudioTrack = nil;
    self.audioSource = nil;
    self.audioProducer = nil;
}

-(void)auth {
    NSLog(@"auth");
    NSDictionary *data = @{@"token": self.token};
    [self request:@"auth"
         jsonData:data
        onSuccess:^(ProtooclientResponse *r) {
        NSLog(@"auth success");
        [self getRouterRtpCapabilities];
    }
          onError:^(ProtooclientResponse *r) {
        
    }];
}

-(void)getRouterRtpCapabilities {
    NSLog(@"getRouterRtpCapabilities");
    [self request:@"getRouterRtpCapabilities"
        onSuccess:^(ProtooclientResponse *r) {
        [self loadDevice:r.data];
        [self createSendTransport];
    }
          onError:^(ProtooclientResponse *r) {
        
    }];
}

-(void)createSendTransport {
    NSLog(@"createSendTransport");
    NSDictionary *data = @{
        @"forceTcp": @(NO),
        @"producing": @(YES),
        @"consuming": @(NO)
    };
    [self request:@"createWebRtcTransport"
         jsonData:data
        onSuccess:^(ProtooclientResponse *r) {
        NSData *data = [r.data dataUsingEncoding:NSUTF8StringEncoding];
        NSError *error = nil;
        NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
        if (error != nil) {
            NSLog(@"json decode error:%@", error);
            return;
        }
        NSString *transportId = [dict objectForKey:@"id"];
        NSDictionary *iceParameters = [dict objectForKey:@"iceParameters"];
        NSArray *iceCandidates = [dict objectForKey:@"iceCandidates"];
        NSDictionary *dtlsParameters = [dict objectForKey:@"dtlsParameters"];
        
        NSString *s_iceParameters = [[self class] objectToJSONString:iceParameters];
        NSString *s_iceCandidates = [[self class] objectToJSONString:iceCandidates];
        NSString *s_dtlsParameters = [[self class] objectToJSONString:dtlsParameters];
        
        self.sendTransport = [self.device createSendTransport:transportId
                                                iceParameters:s_iceParameters
                                                iceCandidates:s_iceCandidates
                                               dtlsParameters:s_dtlsParameters
                                                    rtcConfig:self.rtcConfiguration
                                                      factory:self.factory];
        [self connectTransport:self.sendTransport
                 localDtlsRole:@"server"
                     onSuccess:^(ProtooclientResponse *r) {
            NSLog(@"send transport connect success");
            [self createRecvTransport];
        }
                       onError:^(ProtooclientResponse *r) {
            
        }];
        
    }
          onError:^(ProtooclientResponse *r) {
        
    }];
}

-(void)createRecvTransport {
    NSLog(@"createRecvTransport");
    NSDictionary *data = @{
        @"forceTcp": @(NO),
        @"producing": @(NO),
        @"consuming": @(YES)
    };
    [self request:@"createWebRtcTransport"
         jsonData:data
        onSuccess:^(ProtooclientResponse *r) {
        NSData *data = [r.data dataUsingEncoding:NSUTF8StringEncoding];
        NSError *error = nil;
        NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
        if (error != nil) {
            NSLog(@"json decode error:%@", error);
            return;
        }
        NSString *transportId = [dict objectForKey:@"id"];
        NSDictionary *iceParameters = [dict objectForKey:@"iceParameters"];
        NSArray *iceCandidates = [dict objectForKey:@"iceCandidates"];
        NSDictionary *dtlsParameters = [dict objectForKey:@"dtlsParameters"];
        
        NSString *s_iceParameters = [[self class] objectToJSONString:iceParameters];
        NSString *s_iceCandidates = [[self class] objectToJSONString:iceCandidates];
        NSString *s_dtlsParameters = [[self class] objectToJSONString:dtlsParameters];
        
        self.recvTransport = [self.device createRecvTransport:transportId
                                                iceParameters:s_iceParameters
                                                iceCandidates:s_iceCandidates
                                               dtlsParameters:s_dtlsParameters
                                                    rtcConfig:self.rtcConfiguration
                                                      factory:self.factory];
        
        [self connectTransport:self.recvTransport
                 localDtlsRole:@"client"
                     onSuccess:^(ProtooclientResponse *r) {
            NSLog(@"recv transport:%@ connect success", transportId);
            [self join];
        }
                       onError:^(ProtooclientResponse *r) {
            
        }];
        
    }
          onError:^(ProtooclientResponse *r) {
        
    }];
}


-(void)connectTransport:(MSTransport*)transport localDtlsRole:(NSString*)localDtlsRole onSuccess:(void (^)(ProtooclientResponse*))onSuccess onError:(void(^)(ProtooclientResponse*))onError {
    MSFingerprint *fp = [transport fingerprint];
    NSDictionary *fingerprint = @{@"algorithm":fp.algorithm, @"value":fp.fingerprint};
    NSDictionary *dtlsParameters = @{@"role":localDtlsRole, @"fingerprints":@[fingerprint]};
    
    NSDictionary *data = @{@"transportId":transport.transportId, @"dtlsParameters":dtlsParameters};
    [self request:@"connectWebRtcTransport" jsonData:data onSuccess:onSuccess onError:onError];
}

-(void)join {
    NSObject *rtpCaps = [[self class] JSONStringToObject:self.device.rtpCapabilities];
    NSDictionary *device = @{@"flag":@"ios-native", @"name":@"ios", @"version":@"16"};
    NSDictionary *data = @{
        @"displayName": [NSString stringWithFormat:@"%lld", self.currentUID],
        @"device": device,
        @"produceVideo": @(TRUE),
        @"produceAudio": @(TRUE),
        @"rtpCapabilities": rtpCaps,
    };
    [self request:@"join" jsonData:data
        onSuccess:^(ProtooclientResponse *r) {
        NSLog(@"join room success");
        [self produceAudio];
        [self produceVideo];
        
        NSDictionary *object = [[self class] JSONStringToObject:r.data];
        NSArray *peers = [object objectForKey:@"peers"];
        for (NSUInteger i = 0; i < peers.count; i++) {
            NSDictionary *peer = [peers objectAtIndex:i];
            NSString *peerId = [peer objectForKey:@"id"];
            NSArray *producers = [peer objectForKey:@"producers"];
            for (NSUInteger j = 0; j < producers.count; j++) {
                NSDictionary *producer = [producers objectAtIndex:j];
                NSString *producerId = [producer objectForKey:@"id"];
                [self consumeProducer:producerId peerId:peerId];
            }
        }
    }
          onError:nil];
    
}

-(void)getStats {
    NSString *stats = [self.sendTransport getStats];
    NSString *videoProducerStats = [self.sendTransport getProducerStats:self.videoProducer.localId];
    NSLog(@"send transport stats:%@", stats);
    NSLog(@"video producer stats:%@", videoProducerStats);

    for (Consumer *c in [self.consumers allValues]) {
        NSString *consumerStats = [self.recvTransport GetConsumerStats:c.localId];
        NSLog(@"consumer stats:%@", consumerStats);
    }
}
-(void)produceAudio {
    if (![self.device canProduce:kRTCMediaStreamTrackKindAudio]) {
        NSLog(@"Device can't produce audio");
        return;
    }
    AVAuthorizationStatus audioAuthStatus = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio];
    if (audioAuthStatus != AVAuthorizationStatusAuthorized) {
        NSLog(@"Record audio permission denied");
        return;
    }
    
    NSLog(@"producer audio...");
    RTCMediaConstraints *constraints = [self defaultMediaAudioConstraints];
    RTCAudioSource *source = [self.factory audioSourceWithConstraints:constraints];
    RTCAudioTrack *track = [self.factory audioTrackWithSource:source
                                                      trackId:kARDAudioTrackId];
    
    // TRUE/FALSE is not real bool value and didn't works.
    NSDictionary *codecOptions = @{@"opusStereo":@(YES), @"opusDtx":@(YES)};
    NSString *s_codecOptions = [[self class] objectToJSONString:codecOptions];
    MSSendResult *sendResult = [self.sendTransport produce:track encodings:@[] codecOptions:s_codecOptions codec:nil];
    NSDictionary *rtpParameters = (NSDictionary*)[[self class] JSONStringToObject:sendResult.rtpParameters];
    Producer *producer = [[Producer alloc] init];
    producer.localId = sendResult.localId;
    producer.rtpSender = sendResult.rtpSender;
    producer.track = sendResult.rtpSender.track;
    producer.rtpParameters = rtpParameters;
    self.audioProducer = producer;
    self.audioSource = source;
    self.localAudioTrack = track;
    
    NSDictionary *data = @{
        @"transportId":self.sendTransport.transportId,
        @"kind":kRTCMediaStreamTrackKindAudio,
        @"rtpParameters":rtpParameters,
    };
    
    [self request:@"produce"
         jsonData:data
        onSuccess:^(ProtooclientResponse *r) {
        NSDictionary *dict = [[self class] JSONStringToObject:r.data];
        producer.id_ = [dict objectForKey:@"id"];
        NSLog(@"produce audio success, id:%@", producer.id_);
    }
          onError:nil];
    
}

-(void)produceVideo {
    if (![self.device canProduce:kRTCMediaStreamTrackKindAudio]) {
        NSLog(@"Device can't produce audio");
        return;
    }
    AVAuthorizationStatus authStatus = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    if (authStatus != AVAuthorizationStatusAuthorized) {
        NSLog(@"Camera permission denied");
        return;
    }

    if ([RTCCameraVideoCapturer captureDevices].count == 0) {
        NSLog(@"No capture devices found.");
        return;
    }
    
    NSLog(@"producer video...");
    WebRTCVideoView *videoView = [self createVideoView:@"local" isLocal:TRUE];
    RTCVideoSource *source = [self.factory videoSource];
    RTCCameraVideoCapturer *capturer = [[RTCCameraVideoCapturer alloc] initWithDelegate:source];
    ARDCaptureController *captureController = [[ARDCaptureController alloc] initWithCapturer:capturer with:640 height:480 fps:30];
    [captureController startCapture];
    RTCVideoTrack *localVideoTrack = [self.factory videoTrackWithSource:source
                                                                trackId:kARDVideoTrackId];
    NSLog(@"local video track enabled:%d", localVideoTrack.isEnabled);
    [localVideoTrack addRenderer:videoView];
    //videosource should be strong reference
    self.videoSource = source;
    self.captureController = captureController;
    self.localVideoTrack = localVideoTrack;
    
    NSDictionary *codecOptions = @{@"videoGoogleStartBitrate":@(1000)};
    NSString *codecOptionsJson = [[self class] objectToJSONString:codecOptions];
    MSSendResult *sendResult = [self.sendTransport produce:localVideoTrack encodings:@[] codecOptions:codecOptionsJson codec:nil];
    NSDictionary *rtpParameters = (NSDictionary*)[[self class] JSONStringToObject:sendResult.rtpParameters];
    Producer *producer = [[Producer alloc] init];
    producer.localId = sendResult.localId;
    producer.rtpSender = sendResult.rtpSender;
    producer.track = sendResult.rtpSender.track;
    producer.rtpParameters = rtpParameters;
    
    self.videoProducer = producer;

    NSDictionary *data = @{
        @"transportId":self.sendTransport.transportId,
        @"kind":kRTCMediaStreamTrackKindVideo,
        @"rtpParameters":rtpParameters,
    };
    
    [self request:@"produce"
         jsonData:data
        onSuccess:^(ProtooclientResponse *r) {
        NSDictionary *dict = [[self class] JSONStringToObject:r.data];
        producer.id_ = [dict objectForKey:@"id"];
        NSLog(@"produce video success, id:%@", producer.id_);
    }
          onError:nil];
}

-(void)closeVideoProducer {
    if (!self.videoProducer) {
        return;
    }
    NSLog(@"close video producer");
    [self.captureController stopCapture];
    [self removeVideoView:@"local"];

    [self.sendTransport closeProducer:self.videoProducer.localId];
    NSDictionary *data = @{
        @"producerId":self.videoProducer.id_,
    };
    [self request:@"closeProducer"
         jsonData:data
        onSuccess:^(ProtooclientResponse *r) {
        NSLog(@"closee video producer success, id");
    }
          onError:nil];
    
    self.captureController = nil;
    self.localVideoTrack = nil;
    self.videoSource = nil;
    self.videoProducer = nil;
}

-(void)closeAudioProducer {
    if (!self.audioProducer) {
        return;
    }
    
    [self.sendTransport closeProducer:self.audioProducer.localId];
    NSDictionary *data = @{
        @"producerId":self.audioProducer.id_,
    };
    [self request:@"closeProducer"
         jsonData:data
        onSuccess:^(ProtooclientResponse *r) {
        NSLog(@"closee video producer success, id");
    }
          onError:nil];
    self.localAudioTrack = nil;
    self.audioSource = nil;
    self.audioProducer = nil;
}

-(void)consumeProducer:(NSString*)producerId peerId:(NSString*)peerId {
    NSString *transportId = self.recvTransport.transportId;
    NSLog(@"transport:%@ consume producer:%@ %@", transportId, producerId, peerId);
    NSDictionary *object = @{@"producerId":producerId, @"transportId":transportId};
    [self request:@"consume"
         jsonData:object
        onSuccess:^(ProtooclientResponse *r) {
        
        NSDictionary *data = [[self class] JSONStringToObject:r.data];
        NSString *id_ = [data objectForKey:@"id"];
        NSString *kind = [data objectForKey:@"kind"];
        NSDictionary *rtpParameters = [data objectForKey:@"rtpParameters"];
        NSString *s_rtpParameters = [[self class] objectToJSONString:rtpParameters];
        MSRecvResult *recvResult = [self.recvTransport consume:id_ producerId:producerId kind:kind rtpParameters:s_rtpParameters];

        Consumer *consumer = [[Consumer alloc] init];
        consumer.id_ = id_;
        consumer.localId = recvResult.localId;
        consumer.producerId = producerId;
        consumer.rtpReceiver = recvResult.rtpReceiver;
        consumer.track = recvResult.rtpReceiver.track;
        consumer.rtpParameters = rtpParameters;
        [self.consumers setObject:consumer forKey:consumer.id_];

        if  ([kind isEqualToString:kRTCMediaStreamTrackKindVideo]) {
            NSAssert([consumer.track.kind isEqualToString:kRTCMediaStreamTrackKindVideo], @"");
            WebRTCVideoView *videoView = [self createVideoView:id_ isLocal:NO];
            RTCVideoTrack *videoTrack = (RTCVideoTrack*)consumer.track;
            [videoTrack addRenderer:videoView];
        }
        [self resumeConsume:consumer];
    }
          onError:^(ProtooclientResponse *r) {
        
    }];
}

-(void)resumeConsume:(Consumer*)consumer {
    NSDictionary *object = @{@"consumerId": consumer.id_};
    [self request:@"resumeConsumer" jsonData:object onSuccess:nil onError:nil];
}


-(WebRTCVideoView*)createVideoView:(NSString*)id_ isLocal:(BOOL)isLocal {
    return [self.videoRendererDeleegate createVideoView:id_ isLocal:isLocal];
}

-(void)removeVideoView:(NSString*)id_ {
    [self.videoRendererDeleegate removeVideoView:id_];
}

- (RTCMediaConstraints *)defaultMediaAudioConstraints {
    NSDictionary *mandatoryConstraints = @{};
    RTCMediaConstraints *constraints =
    [[RTCMediaConstraints alloc] initWithMandatoryConstraints:mandatoryConstraints
                                          optionalConstraints:nil];
    return constraints;
}

- (void)request:(NSString*)method onSuccess:(void (^)(ProtooclientResponse*))onSuccess onError:(void(^)(ProtooclientResponse*))onError {
    [self request:method data:@"{}" onSuccess:onSuccess onError:onError];
}

- (void)request:(NSString*)method jsonData:(NSDictionary*)jsonData onSuccess:(void (^)(ProtooclientResponse*))onSuccess onError:(void(^)(ProtooclientResponse*))onError {
    NSData *data = [NSJSONSerialization dataWithJSONObject:jsonData options:0 error:nil];
    NSString *jsonString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    [self request:method data:jsonString onSuccess:onSuccess onError:onError];
}

- (void)request:(NSString*)method data:(NSString*)data onSuccess:(void (^)(ProtooclientResponse*))onSuccess onError:(void(^)(ProtooclientResponse*))onError {
    ProtooclientRequest *req = [[ProtooclientRequest alloc] init:[self generateNextId] method:method data:data];
    NSLog(@"request id:%lld method:%@ data:%@", req.id_, req.method, req.data);
    
    NSError *error = nil;
    [self.peerClient request:req error:&error];
    if (error != nil) {
        NSLog(@"peer client request err:%@", error);
        return;
    }

    PendingRequest *pendingRequest = [[PendingRequest alloc] initWithRequest:req onSuccess:onSuccess onError:onError];
    [self.pendingRequests setObject:pendingRequest forKey:@(req.id_)];
}

-(int64_t)generateNextId {
    self.nextId += 1;
    return self.nextId;
}

-(void)resetNextId {
    self.nextId = 0;
}

-(void)loadDevice:(NSString*)routerRtpCaps {
    NSLog(@"load device router rtp caps:%@", routerRtpCaps);
    self.device = [[MSDevice alloc] init];
    [self.device load:routerRtpCaps rtcConfig:self.rtcConfiguration factory:self.factory];
    NSAssert(self.device.loaded, @"");
    NSLog(@"device loaded:%@ %@", self.device.rtpCapabilities, self.device.sctpCapabilities);
}

+(NSString*)objectToJSONString:(NSObject*)object {
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:0 error:&error];
    if (error != nil) {
        NSLog(@"json encode err:%@", error);
        return nil;
    }
    NSString *jsonString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return jsonString;
}

+(id)JSONStringToObject:(NSString*)s {
    NSData *data = [s dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    NSObject *obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if (error != nil) {
        NSLog(@"json decode error:%@", error);
        return nil;
    }
    return obj;
}

#pragma mark ProtooclientPeerListener
- (void)onClose {
    
}
- (void)onDisconnected {
    
}
- (void)onFailed {
    
}

- (void)onNotification:(ProtooclientNotification* _Nullable)p0 {
    NSLog(@"handle notification:%@ %@", p0.method, p0.data);
    NSString *method = p0.method;

    if ([method isEqualToString:@"newPeer"]) {

    } else if ([method isEqualToString:@"peerClosed"]) {
        
    } else if ([method isEqualToString:@"newProducer"]) {
        NSDictionary *object = [[self class] JSONStringToObject:p0.data];
        NSString *id_ = [object objectForKey:@"id"];
        NSString *kind = [object objectForKey:@"kind"];
        NSString *peerId = [object objectForKey:@"peerId"];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self consumeProducer:id_ peerId:peerId];
        });
    } else if ([method isEqualToString:@"consumerClosed"]) {
        NSDictionary *object = [[self class] JSONStringToObject:p0.data];
        NSString *consumerId = [object objectForKey:@"consumerId"];
        dispatch_async(dispatch_get_main_queue(), ^{
            Consumer *consumer = [self.consumers objectForKey:consumerId];
            if (!consumer) {
                return;
            }
            [self.recvTransport closeConsumer:consumer.localId];
            [self.consumers removeObjectForKey:consumerId];
            if ([consumer.track.kind isEqualToString:@"video"]) {
                [self removeVideoView:consumerId];
            }
        });
    } else if ([method isEqualToString:@"consumerPaused"]) {
        
    } else if ([method isEqualToString:@"consumerResumed"]) {
        
    } else {
        NSLog(@"unhandled notification:%@ %@", p0.method, p0.data);
    }
}

- (void)onOpen {
    NSLog(@"protoo client opened");
    NSAssert(![NSThread isMainThread], @"");
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self resetNextId];
        [self.pendingRequests removeAllObjects];
        [self auth];
    });
}

- (void)onRequest:(ProtooclientRequest* _Nullable)p0 {
    NSLog(@"on request:%lld %@ %@", p0.id_, p0.method, p0.data);
}

- (void)onResponse:(ProtooclientResponse* _Nullable)resp {
    NSLog(@"on response:%lld %@ %d %ld %@", resp.id_, resp.data, resp.ok, resp.errorCode, resp.errorReason);
    
    NSAssert(![NSThread isMainThread], @"");
    dispatch_async(dispatch_get_main_queue(), ^{
        PendingRequest *pendingRequest = [self.pendingRequests objectForKey:@(resp.id_)];
        if (!pendingRequest) {
            NSLog(@"Can't find pending request:%lld", resp.id_);
            return;
        }
        [self.pendingRequests removeObjectForKey:@(resp.id_)];
        if (resp.ok) {
            if (pendingRequest.onSuccess) {
                pendingRequest.onSuccess(resp);
            }
        } else {
            if (pendingRequest.onError) {
                pendingRequest.onError(resp);
            }
        }
    });
}

@end

