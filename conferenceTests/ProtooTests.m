//
//  ProtooTests.m
//  conferenceTests
//
//  Created by houxh on 2023/5/16.
//  Copyright © 2023 beetle. All rights reserved.
//
#import <XCTest/XCTest.h>

#import <Protooclient/Protooclient.h>
#include <netinet/in.h>
#include <netdb.h>
#include <arpa/inet.h>

@interface ProtooclientListener : NSObject<ProtooclientPeerListener>
@property(nonatomic) ProtooclientPeer *peer;
@end

@implementation ProtooclientListener

- (void)onClose {
    
}
- (void)onDisconnected {
    
}
- (void)onFailed {
    
}
- (void)onNotification:(ProtooclientNotification* _Nullable)p0 {
    
}
- (void)onOpen {
    NSLog(@"protoo client opened");
    
    NSDictionary *jsonData = @{@"token": @""};
    
    NSData *data = [NSJSONSerialization dataWithJSONObject:jsonData options:0 error:nil];
    NSString *jsonString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    
    ProtooclientRequest *req = [[ProtooclientRequest alloc] init:1L method:@"auth" data:jsonString];
    NSError *error = nil;
    [self.peer request:req error:&error];

}

- (void)onRequest:(ProtooclientRequest* _Nullable)p0 {
    NSLog(@"on request:%lld %@ %@", p0.id_, p0.method, p0.data);
}

- (void)onResponse:(ProtooclientResponse* _Nullable)p0 {
    NSLog(@"on response:%lld %@", p0.id_, p0.data);
}

@end
@interface ProtooTests : XCTestCase

@end

@implementation ProtooTests

- (void)setUp
{
    [super setUp];
    // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown
{
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}


- (void)testProtooClient
{
    NSLog(@"test protoo client");

    ProtooclientListener *listener = [[ProtooclientListener alloc] init];

    NSString *url = [NSString stringWithFormat:@"ws://192.168.1.101:14444/?peerId=%lld&roomId=%lld&mode=group", 1LL, 1LL];
    ProtooclientPeer *peer = [[ProtooclientPeer alloc] init:url listener:listener];
    
    listener.peer = peer;
    
    [peer open];
    
    sleep(5);
}

-(void)testConnect {
    NSString *host = @"192.168.1.101";
    int port = 14444;
    
    struct sockaddr_in6 addr;
    struct addrinfo addrinfo;
    
    BOOL res = [self synthesizeIPv6:host port:port addr:(struct sockaddr*)&addr addrinfo:&addrinfo];
    if (!res) {
        NSLog(@"synthesize ipv6 fail");
        XCTFail(@"synthesize ipv6 fail");
        return;
    }
    
    int r;
    int sockfd;
    
    sockfd = socket(addrinfo.ai_family, addrinfo.ai_socktype, addrinfo.ai_protocol);
    
    int value = 1;
    setsockopt(sockfd, SOL_SOCKET, SO_NOSIGPIPE, &value, sizeof(value));


    if (addrinfo.ai_family == AF_INET) {
        r = connect(sockfd, (struct sockaddr*)&addr, sizeof(struct sockaddr_in));
    } else {
        //ipv6
        r = connect(sockfd, (struct sockaddr*)&addr, sizeof(struct sockaddr_in6));
    }
    if (r == -1) {
        NSLog(@"connect error:%s", strerror(errno));
        XCTFail(@"connect error");
    }
 
    close(sockfd);

    NSLog(@"connect success");
}

- (BOOL)synthesizeIPv6:(NSString*)host port:(int)port addr:(struct sockaddr*)addr addrinfo:(struct addrinfo*)info {
    int error;
    struct addrinfo hints, *res0, *res;
    const char *ipv4_str = [host UTF8String];
    
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = PF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    hints.ai_flags = AI_DEFAULT;
    error = getaddrinfo(ipv4_str, "", &hints, &res0);
    if (error) {
        NSLog(@"%s", gai_strerror(error));
        return FALSE;
    }

    for (res = res0; res; res = res->ai_next) {
        NSLog(@"family:%d socktype;%d protocol:%d", res->ai_family, res->ai_socktype, res->ai_protocol);
    }
    
    BOOL r = YES;
    //use first
    if (res0) {
        if (res0->ai_family == AF_INET6) {
            struct sockaddr_in6 *addr6 = ((struct sockaddr_in6*)res0->ai_addr);
            addr6->sin6_port = htons(port);
            
            memcpy(addr, res0->ai_addr, res0->ai_addrlen);
            *info = *res0;
        } else if (res0->ai_family == AF_INET) {
            struct sockaddr_in *addr4 = ((struct sockaddr_in*)res0->ai_addr);
            addr4->sin_port = htons(port);
            
            memcpy(addr, res0->ai_addr, res0->ai_addrlen);
            *info = *res0;
        } else {
            r = NO;
        }
    }

    freeaddrinfo(res0);
    return r;
}

@end

