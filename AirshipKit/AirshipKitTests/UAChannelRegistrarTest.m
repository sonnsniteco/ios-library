/* Copyright 2018 Urban Airship and Contributors */

#import "UABaseTest.h"
#import "UAChannelAPIClient+Internal.h"
#import "UAChannelRegistrar+Internal.h"
#import "UAChannelRegistrationPayload+Internal.h"
#import "UAPush.h"
#import "UAConfig.h"
#import "UANamedUser+Internal.h"
#import "UAirship.h"
#import "UAPreferenceDataStore+Internal.h"

@interface UAChannelRegistrarTest : UABaseTest

@property (nonatomic, strong) id mockedChannelClient;
@property (nonatomic, strong) id mockedRegistrarDelegate;
@property (nonatomic, strong) id mockedUAPush;
@property (nonatomic, strong) id mockedUAirship;
@property (nonatomic, strong) id mockedUAConfig;
@property (nonatomic, strong) id mockedDataStore;


@property (nonatomic, assign) NSUInteger failureCode;
@property (nonatomic, copy) NSString *channelCreateSuccessChannelID;
@property (nonatomic, copy) NSString *channelCreateSuccessChannelLocation;

@property (nonatomic, strong) UAChannelRegistrationPayload *payload;
@property (nonatomic, strong) UAChannelRegistrar *registrar;
@property bool clearNamedUser;
@property bool existing;

@end

@implementation UAChannelRegistrarTest

void (^channelUpdateSuccessDoBlock)(NSInvocation *);
void (^channelCreateSuccessDoBlock)(NSInvocation *);
void (^channelUpdateFailureDoBlock)(NSInvocation *);
void (^channelCreateFailureDoBlock)(NSInvocation *);

void (^deviceRegisterSuccessDoBlock)(NSInvocation *);

- (void)setUp {
    [super setUp];

    self.existing = YES;
    self.clearNamedUser = YES;

    self.channelCreateSuccessChannelID = @"newChannelID";
    self.channelCreateSuccessChannelLocation = @"newChannelLocation";

    self.mockedChannelClient = [self mockForClass:[UAChannelAPIClient class]];

    self.mockedRegistrarDelegate = [self mockForProtocol:@protocol(UAChannelRegistrarDelegate)];

    self.mockedUAPush = [self mockForClass:[UAPush class]];

    self.mockedUAConfig = [self mockForClass:[UAConfig class]];
    [[[self.mockedUAConfig stub] andDo:^(NSInvocation *invocation) {
        [invocation setReturnValue:&self->_clearNamedUser];
    }] clearNamedUserOnAppRestore];

    self.mockedUAirship = [self mockForClass:[UAirship class]];
    [[[self.mockedUAirship stub] andReturn:self.mockedUAirship] shared];
    [[[self.mockedUAirship stub] andReturn:self.mockedUAConfig] config];
    [[[self.mockedUAirship stub] andReturn:self.mockedUAPush] push];

    self.registrar = [[UAChannelRegistrar alloc] init];
    self.registrar.dataStore = [UAPreferenceDataStore preferenceDataStoreWithKeyPrefix:@"com.urbanairship.%@."];
    self.registrar.channelAPIClient = self.mockedChannelClient;
    self.registrar.delegate = self.mockedRegistrarDelegate;

    self.mockedDataStore = [OCMockObject niceMockForClass:[UAPreferenceDataStore class]];
    self.registrar.dataStore = self.mockedDataStore;

    self.payload = [[UAChannelRegistrationPayload alloc] init];
    self.payload.pushAddress = @"someDeviceToken";

    self.failureCode = 400;

    channelUpdateSuccessDoBlock = ^(NSInvocation *invocation) {
        void *arg;
        [invocation getArgument:&arg atIndex:4];
        UAChannelAPIClientUpdateSuccessBlock successBlock = (__bridge UAChannelAPIClientUpdateSuccessBlock)arg;
        successBlock();
    };

    channelUpdateFailureDoBlock = ^(NSInvocation *invocation) {
        void *arg;
        [invocation getArgument:&arg atIndex:5];
        UAChannelAPIClientFailureBlock failureBlock = (__bridge UAChannelAPIClientFailureBlock)arg;
        failureBlock(self.failureCode);
    };

    channelCreateSuccessDoBlock = ^(NSInvocation *invocation) {
        void *arg;
        [invocation getArgument:&arg atIndex:3];
        UAChannelAPIClientCreateSuccessBlock successBlock = (__bridge UAChannelAPIClientCreateSuccessBlock)arg;
        successBlock(self.channelCreateSuccessChannelID, self.channelCreateSuccessChannelLocation, self.existing);
    };

    channelCreateFailureDoBlock = ^(NSInvocation *invocation) {
        void *arg;
        [invocation getArgument:&arg atIndex:4];
        UAChannelAPIClientFailureBlock failureBlock = (__bridge UAChannelAPIClientFailureBlock)arg;
        failureBlock(self.failureCode);
    };
}

- (void)tearDown {
    [self.mockedChannelClient stopMocking];
    [self.mockedRegistrarDelegate stopMocking];
    [self.mockedUAConfig stopMocking];
    [self.mockedUAPush stopMocking];
    [self.mockedDataStore stopMocking];
    [self.mockedUAirship stopMocking];

    [super tearDown];
}

/**
 * Test successful register with a channel
 */
- (void)testRegisterWithChannel {
    // Expect the channel client to update channel and call the update block
    [[[self.mockedChannelClient expect] andDo:channelUpdateSuccessDoBlock] updateChannelWithLocation:@"someLocation"
                                                                                         withPayload:[OCMArg checkWithSelector:@selector(isEqualToPayload:) onObject:self.payload]
                                                                                           onSuccess:OCMOCK_ANY
                                                                                           onFailure:OCMOCK_ANY];

    // Expect the delegate to be called
    [self expectRegistrationSucceededWithPayload:self.payload];

    [self.registrar registerWithChannelID:@"someChannel" channelLocation:@"someLocation" withPayload:self.payload forcefully:NO];
    [self waitForExpectationsWithTimeout:1 handler:nil];

    XCTAssertNoThrow([self.mockedChannelClient verify], @"Registering should always cancel all requests and call updateChannel with passed payload and channel ID.");
    XCTAssertNoThrow([self.mockedRegistrarDelegate verify], @"Delegate should be called.");
}

/**
 * Test failed register with a channnel
 */
- (void)testRegisterWithChannelFail {
    // Expect the channel client to update channel and call the update block
    [[[self.mockedChannelClient expect] andDo:channelUpdateFailureDoBlock] updateChannelWithLocation:@"someLocation"
                                                                                         withPayload:[OCMArg checkWithSelector:@selector(isEqualToPayload:) onObject:self.payload]
                                                                                           onSuccess:OCMOCK_ANY
                                                                                           onFailure:OCMOCK_ANY];

    // Expect the delegate to be called
    [self expectRegistrationFailureWithPayload:self.payload];

    [self.registrar registerWithChannelID:@"someChannel" channelLocation:@"someLocation" withPayload:self.payload forcefully:NO];

    [self waitForExpectationsWithTimeout:1 handler:nil];

    XCTAssertNoThrow([self.mockedChannelClient verify], @"Registering should always cancel all requests and call updateChannel with passed payload and channel ID.");
    XCTAssertNoThrow([self.mockedRegistrarDelegate verify], @"Delegate should be called on failure");

}

/**
 * Test register with a channel ID with the same payload as the last successful
 * registration payload results in update if 24 hours has passed since last update
 * and is rejected otherwise.
 */
- (void)testRegisterWithChannelDuplicateAfter24Hours{
    // Expect the channel client to update channel and call the update block
    [[[self.mockedChannelClient expect] andDo:channelUpdateSuccessDoBlock] updateChannelWithLocation:OCMOCK_ANY
                                                                                         withPayload:OCMOCK_ANY
                                                                                           onSuccess:OCMOCK_ANY
                                                                                           onFailure:OCMOCK_ANY];
    // Set the last payload to the current payload
    self.registrar.lastSuccessfulPayload = self.payload;

    // Mock last update time to two days ago
    NSTimeInterval k24HoursInSecondsInPast = -(24 * 60 * 60);
    [[[self.mockedDataStore stub] andReturn:[NSDate dateWithTimeInterval:k24HoursInSecondsInPast sinceDate:[NSDate date]]] objectForKey:@"last-update-key"];

    // Mock the storage of the last payload
    [[[self.mockedDataStore stub] andReturn:self.payload.asJSONData] objectForKey:@"payload-key"];

    // Expect the delegate to be called
    [self expectRegistrationSucceededWithPayload:self.payload];

    // Make the request
    [self.registrar registerWithChannelID:@"someChannel" channelLocation:@"someLocation" withPayload:self.payload forcefully:NO];
    [self waitForExpectationsWithTimeout:1 handler:nil];

    XCTAssertNoThrow([self.mockedRegistrarDelegate verify], @"Delegate should be called on success");
    XCTAssertNoThrow([self.mockedChannelClient verify], @"Registering with a payload that is already registered should skip");

    // Mock last update time to current time/date
    [[[self.mockedDataStore stub] andReturn:[NSDate date]] objectForKey:@"last-update-key"];

    // Reject any update channel calls
    [[[self.mockedChannelClient expect] andDo:channelUpdateSuccessDoBlock] updateChannelWithLocation:OCMOCK_ANY
                                                                                         withPayload:OCMOCK_ANY
                                                                                           onSuccess:OCMOCK_ANY
                                                                                           onFailure:OCMOCK_ANY];
    // Make the request
    [self.registrar registerWithChannelID:@"someChannel" channelLocation:@"someLocation" withPayload:self.payload forcefully:NO];

    XCTAssertNoThrow([self.mockedRegistrarDelegate verify], @"Delegate should be called on success");
    XCTAssertNoThrow([self.mockedChannelClient verify], @"Registering with a payload that is already registered should skip");
}


/**
 * Test register with a channel ID with the same payload as the last successful
 * registration payload.
 */
- (void)testRegisterWithChannelDuplicate {

    // Expect the channel client to update channel and call the update block
    [[[self.mockedChannelClient expect] andDo:channelUpdateSuccessDoBlock] updateChannelWithLocation:@"someLocation"
                                                                                         withPayload:[OCMArg checkWithSelector:@selector(isEqualToPayload:) onObject:self.payload]
                                                                                           onSuccess:OCMOCK_ANY
                                                                                           onFailure:OCMOCK_ANY];
    // Expect the delegate to be called
    [self expectRegistrationSucceededWithPayload:self.payload];

    // Add a successful request
    [self.registrar registerWithChannelID:@"someChannel" channelLocation:@"someLocation" withPayload:self.payload forcefully:NO];
    [self waitForExpectationsWithTimeout:1 handler:nil];

    // Expect it again when we call run it forcefully
    [[[self.mockedChannelClient expect] andDo:channelUpdateSuccessDoBlock] updateChannelWithLocation:@"someLocation"
                                                                                         withPayload:[OCMArg checkWithSelector:@selector(isEqualToPayload:) onObject:self.payload]
                                                                                           onSuccess:OCMOCK_ANY
                                                                                           onFailure:OCMOCK_ANY];
    // Expect the delegate to be called
    [self expectRegistrationSucceededWithPayload:self.payload];

    // Mock the storage of the last payload
    [[[self.mockedDataStore stub] andReturn:self.payload.asJSONData] objectForKey:@"payload-key"];

    // Run it again forcefully
    [self.registrar registerWithChannelID:@"someChannel" channelLocation:@"someLocation" withPayload:self.payload forcefully:YES];
    [self waitForExpectationsWithTimeout:1 handler:nil];

    XCTAssertNoThrow([self.mockedChannelClient verify], @"Registering forcefully should not care about previous requests.");
    XCTAssertNoThrow([self.mockedRegistrarDelegate verify], @"Delegate should be called");

    // Reject a update call on another non-forceful update with the same payload
    [[self.mockedChannelClient reject] updateChannelWithLocation:OCMOCK_ANY
                                                     withPayload:OCMOCK_ANY
                                                       onSuccess:OCMOCK_ANY
                                                       onFailure:OCMOCK_ANY];

    // Delegate should still be called
    [self expectRegistrationSucceededWithPayload:self.payload];

    // Mock last update time to current time/date
    [[[self.mockedDataStore stub] andReturn:[NSDate date]] objectForKey:@"last-update-key"];

    // Run it one more time non-forcefully
    [self.registrar registerWithChannelID:@"someChannel" channelLocation:@"someLocation" withPayload:self.payload forcefully:NO];
    [self waitForExpectationsWithTimeout:1 handler:nil];

    XCTAssertNoThrow([self.mockedChannelClient verify], @"Registering with a payload that is already registered should skip");
    XCTAssertNoThrow([self.mockedRegistrarDelegate verify], @"Delegate should be called on failure");
}

/**
 * Test register without a channel creates a channel
 */
- (void)testRegisterNoChannel {
    // Expect the channel client to create a channel and call success block
    [[[self.mockedChannelClient expect] andDo:channelCreateSuccessDoBlock] createChannelWithPayload:[OCMArg checkWithSelector:@selector(isEqualToPayload:) onObject:self.payload]
                                                                                          onSuccess:OCMOCK_ANY
                                                                                          onFailure:OCMOCK_ANY];

    [self expectRegistrationSucceededWithPayload:self.payload];
    [self expecRegistrationChannelCreatedWithChannelID:self.channelCreateSuccessChannelID location:self.channelCreateSuccessChannelLocation existing:YES];

    [self.registrar registerWithChannelID:nil channelLocation:nil withPayload:self.payload forcefully:NO];
    [self waitForExpectationsWithTimeout:1 handler:nil];

    XCTAssertNoThrow([self.mockedChannelClient verify], @"Channel client should create a new create request");
    XCTAssertNoThrow([self.mockedRegistrarDelegate verify], @"Delegate should be called on success");
}

/**
 * Test register without a channel location fails to creates a channel
 */
- (void)testRegisterNoChannelLocation {
    // Expect the channel client to fail to create a channel and call failure block
    [[[self.mockedChannelClient expect] andDo:channelCreateFailureDoBlock] createChannelWithPayload:[OCMArg checkWithSelector:@selector(isEqualToPayload:) onObject:self.payload]
                                                                                          onSuccess:OCMOCK_ANY
                                                                                          onFailure:OCMOCK_ANY];

    // Expect the delegate to be called
    [self expectRegistrationFailureWithPayload:self.payload];

    [self.registrar registerWithChannelID:@"someChannel" channelLocation:nil withPayload:self.payload forcefully:NO];
    [self waitForExpectationsWithTimeout:1 handler:nil];


    XCTAssertNoThrow([self.mockedChannelClient verify], @"Channel client should create a new create request");
    XCTAssertNoThrow([self.mockedRegistrarDelegate verify], @"Delegate should be called on failure");
}

/**
 * Test that registering when a request is in progress
 * does not attempt to register again
 */
- (void)testRegisterRequestInProgress {
    // Expect the channel client to create a channel and not call either block so the
    // request stays pending
    [[self.mockedChannelClient expect] createChannelWithPayload:OCMOCK_ANY
                                                      onSuccess:OCMOCK_ANY
                                                      onFailure:OCMOCK_ANY];

    // Make a pending request
    [self.registrar registerWithChannelID:nil channelLocation:nil withPayload:self.payload forcefully:NO];

    // Reject any registration requests
    [[self.mockedChannelClient reject] updateChannelWithLocation:OCMOCK_ANY withPayload:OCMOCK_ANY onSuccess:OCMOCK_ANY onFailure:OCMOCK_ANY];
    [[self.mockedChannelClient reject] createChannelWithPayload:OCMOCK_ANY onSuccess:OCMOCK_ANY onFailure:OCMOCK_ANY];

    XCTAssertNoThrow([self.registrar registerWithChannelID:nil channelLocation:nil withPayload:self.payload forcefully:NO], @"A pending request should ignore any further requests.");
    XCTAssertNoThrow([self.registrar registerWithChannelID:nil channelLocation:nil withPayload:self.payload forcefully:YES], @"A pending request should ignore any further requests.");
}

/**
 * Test cancelAllRequests
 */
- (void)testCancelAllRequests {
    self.registrar.lastSuccessfulPayload = [[UAChannelRegistrationPayload alloc] init];
    self.registrar.isRegistrationInProgress = NO;
    [[self.mockedChannelClient expect] cancelAllRequests];

    [self.registrar cancelAllRequests];
    XCTAssertNoThrow([self.mockedChannelClient verify], @"Channel client should cancel all of its requests.");
    // Using the preference store apparently makes this impossible to test
    //XCTAssertNotNil(self.registrar.lastSuccessfulPayload, @"Last success payload should not be cleared if a request is not in progress.");

    self.registrar.isRegistrationInProgress = YES;
    [[self.mockedChannelClient expect] cancelAllRequests];

    [self.registrar cancelAllRequests];
    XCTAssertNil(self.registrar.lastSuccessfulPayload, @"Last success payload should be cleared if a request is in progress.");
    XCTAssertNoThrow([self.mockedChannelClient verify], @"Channel client should cancel all of its requests.");
}

/**
 * Test that a channel update with a 409 status tries to
 * create a new channel ID.
 */
- (void)testChannelConflictNewChannel {
    self.failureCode = 409;

    //Expect the channel client to update channel and call the update block
    [[[self.mockedChannelClient expect] andDo:channelUpdateFailureDoBlock] updateChannelWithLocation:@"someLocation"
                                                                                         withPayload:[OCMArg checkWithSelector:@selector(isEqualToPayload:) onObject:self.payload]
                                                                                           onSuccess:OCMOCK_ANY
                                                                                           onFailure:OCMOCK_ANY];

    // Expect the create channel to be called, make it successful
    self.channelCreateSuccessChannelID = @"newChannel";
    [[[self.mockedChannelClient expect] andDo:channelCreateSuccessDoBlock] createChannelWithPayload:[OCMArg checkWithSelector:@selector(isEqualToPayload:) onObject:self.payload]
                                                                                          onSuccess:OCMOCK_ANY
                                                                                          onFailure:OCMOCK_ANY];

    // Expect the delegate to be called
    [self expectRegistrationSucceededWithPayload:self.payload];

    [[self.mockedRegistrarDelegate expect] channelCreated:@"newChannel" channelLocation:self.channelCreateSuccessChannelLocation existing:YES];


    [self.registrar registerWithChannelID:@"someChannel" channelLocation:@"someLocation" withPayload:self.payload forcefully:NO];
    [self waitForExpectationsWithTimeout:1 handler:nil];

    XCTAssertNoThrow([self.mockedChannelClient verify], @"Conflict with the channel ID should create a new channel");
    XCTAssertNoThrow([self.mockedRegistrarDelegate verify], @"Registration delegate should be called with the new channel");
}

/**
 * Test that a channel update with a 409 fails to create a new
 * channel.
 */
- (void)testChannelConflictFailed {
    self.failureCode = 409;

    //Expect the channel client to update channel and call the update block
    [[[self.mockedChannelClient expect] andDo:channelUpdateFailureDoBlock] updateChannelWithLocation:@"someLocation"
                                                                                         withPayload:[OCMArg checkWithSelector:@selector(isEqualToPayload:) onObject:self.payload]
                                                                                           onSuccess:OCMOCK_ANY
                                                                                           onFailure:OCMOCK_ANY];

    // Expect the create channel to be called, make it fail
    [[[self.mockedChannelClient expect] andDo:channelCreateFailureDoBlock] createChannelWithPayload:[OCMArg checkWithSelector:@selector(isEqualToPayload:) onObject:self.payload]
                                                                                          onSuccess:OCMOCK_ANY
                                                                                          onFailure:OCMOCK_ANY];

    // Expect the delegate to be called
    [self expectRegistrationFailureWithPayload:self.payload];

    [self.registrar registerWithChannelID:@"someChannel" channelLocation:@"someLocation" withPayload:self.payload forcefully:NO];
    [self waitForExpectationsWithTimeout:1 handler:nil];

    XCTAssertNoThrow([self.mockedChannelClient verify], @"Conflict with the channel ID should try to create a new channel");
    XCTAssertNoThrow([self.mockedRegistrarDelegate verify], @"Delegate should be called on failure");
}

/**
 * Test disassociate when channel existed and flag is YES.
 */
- (void)testDisassociateChannelExistFlagYes {
    // set to an existing channel
    self.existing = YES;

    // set clearNamedUserOnAppRestore
    self.clearNamedUser = YES;

    // Expect the channel client to create a channel and call success block
    [[[self.mockedChannelClient expect] andDo:channelCreateSuccessDoBlock] createChannelWithPayload:[OCMArg checkWithSelector:@selector(isEqualToPayload:) onObject:self.payload]
                                                                                          onSuccess:OCMOCK_ANY
                                                                                          onFailure:OCMOCK_ANY];

    [self expectRegistrationSucceededWithPayload:self.payload];
    [self expecRegistrationChannelCreatedWithChannelID:self.channelCreateSuccessChannelID location:self.channelCreateSuccessChannelLocation existing:YES];

    [self.registrar registerWithChannelID:nil channelLocation:nil withPayload:self.payload forcefully:NO];
    [self waitForExpectationsWithTimeout:1 handler:nil];

    XCTAssertNoThrow([self.mockedChannelClient verify], @"Channel client should create a new create request");
    XCTAssertNoThrow([self.mockedRegistrarDelegate verify], @"Delegate should be called on success");
}

/**
 * Test disassociate not called when channel is new and flag is YES
 */
- (void)testNewChannelFlagYes {
    // set to new channel
    self.existing = NO;

    // set clearNamedUserOnAppRestore
    self.clearNamedUser = YES;

    // Expect the channel client to create a channel and call success block
    [[[self.mockedChannelClient expect] andDo:channelCreateSuccessDoBlock] createChannelWithPayload:[OCMArg checkWithSelector:@selector(isEqualToPayload:) onObject:self.payload]
                                                                                          onSuccess:OCMOCK_ANY
                                                                                          onFailure:OCMOCK_ANY];

    [self expectRegistrationSucceededWithPayload:self.payload];
    [self expecRegistrationChannelCreatedWithChannelID:self.channelCreateSuccessChannelID location:self.channelCreateSuccessChannelLocation existing:NO];

    [self.registrar registerWithChannelID:nil channelLocation:nil withPayload:self.payload forcefully:NO];
    [self waitForExpectationsWithTimeout:1 handler:nil];

    XCTAssertNoThrow([self.mockedChannelClient verify], @"Channel client should create a new create request");
    XCTAssertNoThrow([self.mockedRegistrarDelegate verify], @"Delegate should be called on success");
}

/**
 * Test disassociate not called when channel existed and flag is NO
 */
- (void)testChannelExistFlagNo {
    // set to an existing channel
    self.existing = YES;

    // set clearNamedUserOnAppRestore
    self.clearNamedUser = NO;

    // Expect the channel client to create a channel and call success block
    [[[self.mockedChannelClient expect] andDo:channelCreateSuccessDoBlock] createChannelWithPayload:[OCMArg checkWithSelector:@selector(isEqualToPayload:) onObject:self.payload]
                                                                                          onSuccess:OCMOCK_ANY
                                                                                          onFailure:OCMOCK_ANY];

    [self expectRegistrationSucceededWithPayload:self.payload];
    [self expecRegistrationChannelCreatedWithChannelID:self.channelCreateSuccessChannelID location:self.channelCreateSuccessChannelLocation existing:YES];

    [self.registrar registerWithChannelID:nil channelLocation:nil withPayload:self.payload forcefully:NO];
    [self waitForExpectationsWithTimeout:1 handler:nil];

    XCTAssertNoThrow([self.mockedChannelClient verify], @"Channel client should create a new create request");
    XCTAssertNoThrow([self.mockedRegistrarDelegate verify], @"Delegate should be called on success");
}

/**
 * Test disassociate not called when channel is new and flag is NO
 */
- (void)testNewChannelFlagNo {
    // set to new channel
    self.existing = NO;

    // set clearNamedUserOnAppRestore
    self.clearNamedUser = NO;

    // Expect the channel client to create a channel and call success block
    [[[self.mockedChannelClient expect] andDo:channelCreateSuccessDoBlock] createChannelWithPayload:[OCMArg checkWithSelector:@selector(isEqualToPayload:) onObject:self.payload]
                                                                                          onSuccess:OCMOCK_ANY
                                                                                          onFailure:OCMOCK_ANY];

    [self expectRegistrationSucceededWithPayload:self.payload];
    [self expecRegistrationChannelCreatedWithChannelID:self.channelCreateSuccessChannelID location:self.channelCreateSuccessChannelLocation existing:NO];

    [self.registrar registerWithChannelID:nil channelLocation:nil withPayload:self.payload forcefully:NO];
    [self waitForExpectationsWithTimeout:1 handler:nil];

    XCTAssertNoThrow([self.mockedChannelClient verify], @"Channel client should create a new create request");
    XCTAssertNoThrow([self.mockedRegistrarDelegate verify], @"Delegate should be called on success");
}

- (void)testLastSuccessfulUpdate {
    NSDate *now = [NSDate date];
    
    [[self.mockedDataStore expect] setObject:now forKey:@"last-update-key"];

    self.registrar.lastSuccessfulUpdateDate = now;
    
    XCTAssertNoThrow([self.mockedDataStore verify], @"last update timestamp should have been stored");

    [[[self.mockedDataStore expect] andReturn:now] objectForKey:@"last-update-key"];

    XCTAssertEqualObjects(self.registrar.lastSuccessfulUpdateDate, now);
    XCTAssertNoThrow([self.mockedDataStore verify], @"last update timestamp should have been stored and retrieved");
}

- (void)expectRegistrationSucceededWithPayload:(UAChannelRegistrationPayload *)payload {
    XCTestExpectation *expectation = [self expectationWithDescription:@"registrationSucceededWithPayload:"];

    [[[self.mockedRegistrarDelegate expect] andDo:^(NSInvocation *invocation) {
        [expectation fulfill];
    }] registrationSucceededWithPayload:[OCMArg checkWithSelector:@selector(isEqualToPayload:)
                                                         onObject:payload]];
}

- (void)expectRegistrationFailureWithPayload:(UAChannelRegistrationPayload *)payload {
    XCTestExpectation *expectation = [self expectationWithDescription:@"registrationFailedWithPayload:"];

    [[[self.mockedRegistrarDelegate expect] andDo:^(NSInvocation *invocation) {
        [expectation fulfill];
    }] registrationFailedWithPayload:[OCMArg checkWithSelector:@selector(isEqualToPayload:)
                                                      onObject:payload]];
}

- (void)expecRegistrationChannelCreatedWithChannelID:(NSString *)channelId location:(NSString *)location existing:(BOOL)existing {
    XCTestExpectation *expectation = [self expectationWithDescription:@"channelCreated:location:existing:"];

    [[[self.mockedRegistrarDelegate expect] andDo:^(NSInvocation *invocation) {
        [expectation fulfill];
    }] channelCreated:channelId channelLocation:location existing:existing];
}

@end
