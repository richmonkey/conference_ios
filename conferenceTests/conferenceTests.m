//
//  FaceTests.m
//  FaceTests
//
//  Created by houxh on 14-10-13.
//  Copyright (c) 2014年 beetle. All rights reserved.
//

#import <XCTest/XCTest.h>

@interface FaceTests : XCTestCase

@end

@implementation FaceTests

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


- (void)testHistoryDB
{
    NSLog(@"test history db");

}

-(void)testJson
{
    NSDictionary *codecOptions = @{@"opusStereo":@(YES), @"opusDtx":@(YES)};
    NSString *s_codecOptions = [[self class] objectToJSONString:codecOptions];
    NSLog(@"json:%@", s_codecOptions);
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

+(NSObject*)JSONStringToObject:(NSString*)s {
    NSData *data = [s dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    NSObject *obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if (error != nil) {
        NSLog(@"json decode error:%@", error);
        return nil;
    }
    return obj;
}
@end
