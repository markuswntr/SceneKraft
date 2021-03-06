//
//  MainWindowController.m
//  SceneKraft
//
//  Created by Tom Irving on 08/09/2012.
//  Copyright (c) 2012 Tom Irving. All rights reserved.
//

#import "MainWindowController.h"
#import "PlayerNode.h"
#import "BlockNode.h"
#define DEG_TO_RAD(x) (x * 180 / M_PI)

// Standard units.
CGFloat const kGravityAcceleration = -9.80665;
CGFloat const kJumpHeight = 1.2;
CGFloat const kPlayerMovementSpeed = 1.4;

CGFloat const kWorldSize = 10;

@interface MainWindowController () <NSWindowDelegate>
@property (nonatomic, retain) SCNHitTestResult * hitTestResult;
@property (nonatomic, assign) BOOL gameLoopRunning;
- (void)setupScene;
- (void)generateWorld;
- (void)addNodeAtPosition:(SCNVector3)position type:(BlockNodeType)type;
- (void)deselectHighlightedBlock;
- (void)highlightBlockAtCenter;
- (void)setupGameLoop;
- (CVReturn)gameLoopAtTime:(CVTimeStamp)time;
@end

@implementation MainWindowController
@synthesize gameLoopRunning;
@synthesize hitTestResult;

#pragma mark - Window Initialization
- (id)init {
	
	if ((self = [super init])){
		
		trackingArea = nil;
		gameLoopRunning = NO;
		displayLinkRef = NULL;
		
		NSWindow * window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 400, 400)
														styleMask:(NSTitledWindowMask | NSClosableWindowMask | NSResizableWindowMask) backing:NSBackingStoreBuffered defer:YES];
		[window setFrameAutosaveName:@"MainWindow"];
		[window setTitle:@"SceneKraft"];
		[window setDelegate:self];
		[self setWindow:window];
		[window release];
		
		NSView * contentView = window.contentView;
		
		sceneView = [[SCNView alloc] initWithFrame:contentView.bounds];
		[sceneView setAutoresizingMask:(NSViewHeightSizable | NSViewWidthSizable)];
		[sceneView setBackgroundColor:[NSColor blueColor]];
		[contentView addSubview:sceneView];
		[sceneView release];
		
		[sceneView setNextResponder:self];
		[self windowDidResize:nil];
		
		[self setupScene];
		[self setupGameLoop];
	}
	
	return self;
}

#pragma mark - Window Delegate
- (void)windowDidResize:(NSNotification *)notification {
	
	[sceneView removeTrackingArea:trackingArea];
	trackingArea = [[NSTrackingArea alloc] initWithRect:sceneView.bounds
												options:(NSTrackingActiveInKeyWindow | NSTrackingMouseMoved) owner:self userInfo:nil];
	[sceneView addTrackingArea:trackingArea];
	[trackingArea release];
}

- (void)windowDidResignKey:(NSNotification *)notification {
	[playerNode setMovement:SCNVector4Make(0, 0, 0, 0)];
}

#pragma mark - Property Overrides
- (void)setGameLoopRunning:(BOOL)running {
	
	if (gameLoopRunning != running){
		gameLoopRunning = running;
		
		CGAssociateMouseAndMouseCursorPosition(gameLoopRunning ? FALSE : TRUE);
		
		if (gameLoopRunning){
			[NSCursor hide];
			CVDisplayLinkStart(displayLinkRef);
		}
		else
		{
			CVDisplayLinkStop(displayLinkRef);
			[NSCursor unhide];
		}
	}
}

#pragma mark - Scene Initialization
- (void)setupScene {
	
	[sceneView setScene:[SCNScene scene]];
	
	playerNode = [PlayerNode node];
	[playerNode rotateByAmount:CGSizeMake(0, M_PI / 2)];
	[playerNode setPosition:SCNVector3Make(kWorldSize / 2, 0, kWorldSize * 2)];
	[sceneView.scene.rootNode addChildNode:playerNode];
	
	SCNLight * worldLight = [SCNLight light];
	[worldLight setType:SCNLightTypeDirectional];
	[sceneView.scene.rootNode setLight:worldLight];
	
	[self generateWorld];
}

- (void)generateWorld {
	
	for (CGFloat x = 0; x < kWorldSize; x++){
		for (CGFloat y = 0; y < kWorldSize; y++){
			for (CGFloat z = 0; z < kWorldSize; z++){
				[self addNodeAtPosition:SCNVector3Make(x, y, z) type:BlockNodeTypeDirt];
			}
		}
	}
}

#pragma mark - Scene Helpers
- (void)addNodeAtPosition:(SCNVector3)position type:(BlockNodeType)type {
	
	BlockNode * blockNode = [BlockNode blockNodeWithType:type];
	[blockNode setPosition:position];
	[sceneView.scene.rootNode addChildNode:blockNode];
}

- (void)highlightBlockAtCenter {
	
	[self deselectHighlightedBlock];
	
	if (gameLoopRunning){
		CGPoint point = CGPointMake(sceneView.bounds.size.width / 2, sceneView.bounds.size.height / 2);
		NSArray * results = [sceneView hitTest:point options:@{SCNHitTestSortResultsKey:@YES}];
		[results enumerateObjectsUsingBlock:^(SCNHitTestResult *result, NSUInteger idx, BOOL *stop) {
			
			if (result.node != playerNode && [result.node.geometry isKindOfClass:[SCNBox class]]){
				[self setHitTestResult:result];
				*stop = YES;
			}
		}];
		
		//[hitTestResult.node.geometry.firstMaterial.reflective setBorderColor:[NSColor blackColor]];
	}
}

- (void)deselectHighlightedBlock {
	
	//[hitTestResult.node.geometry.firstMaterial.diffuse setContents:(id)[[NSColor redColor] CGColor]];
	[self setHitTestResult:nil];
}

#pragma mark - Game Loop
- (void)setupGameLoop {
	
	if (CVDisplayLinkCreateWithActiveCGDisplays(&displayLinkRef) == kCVReturnSuccess){
		CVDisplayLinkSetOutputCallback(displayLinkRef, DisplayLinkCallback, self);
		[self setGameLoopRunning:YES];
	}
}

static CVReturn DisplayLinkCallback(CVDisplayLinkRef displayLink, const CVTimeStamp *inNow, const CVTimeStamp *inOutputTime,
									CVOptionFlags flagsIn, CVOptionFlags *flagsOut, void *displayLinkContext){
	return [(MainWindowController *)displayLinkContext gameLoopAtTime:*inOutputTime];
}

- (CVReturn)gameLoopAtTime:(CVTimeStamp)time {
	
	dispatch_async(dispatch_get_main_queue(), ^{
		
		CGFloat refreshPeriod = CVDisplayLinkGetActualOutputVideoRefreshPeriod(displayLinkRef);
		
		[playerNode setAcceleration:SCNVector3Make(0, 0, kGravityAcceleration)];
		[playerNode updatePositionWithRefreshPeriod:refreshPeriod];
		[playerNode checkCollisionWithNodes:sceneView.scene.rootNode.childNodes];
		
		SCNVector3 playerNodePosition = playerNode.position;
		if (playerNodePosition.z < 0) playerNodePosition.z = kWorldSize * 2;
		[playerNode setPosition:playerNodePosition];
		
		[self highlightBlockAtCenter];
		[self.window setTitle:[NSString stringWithFormat:@"SceneKraft - %.f FPS", (1 / refreshPeriod)]];
	});
	
	return kCVReturnSuccess;
}

#pragma mark - Event Handling
- (void)keyDown:(NSEvent *)theEvent {
	
	SCNVector4 movement = playerNode.movement;
	if (theEvent.keyCode == 126 || theEvent.keyCode == 13) movement.x = kPlayerMovementSpeed;
	if (theEvent.keyCode == 123 || theEvent.keyCode == 0) movement.y = kPlayerMovementSpeed;
	if (theEvent.keyCode == 125 || theEvent.keyCode == 1) movement.z = kPlayerMovementSpeed;
	if (theEvent.keyCode == 124 || theEvent.keyCode == 2) movement.w = kPlayerMovementSpeed;
	[playerNode setMovement:movement];
	
	if (theEvent.keyCode == 49 && playerNode.touchingGround){
		
		// v^2 = u^2 + 2as
		// 0 = u^2 + 2as (v = 0 at top of jump)
		// -u^2 = 2as;
		// u^2 = -2as;
		// u = sqrt(-2 * kGravityAcceleration * kJumpHeight)
		
		SCNVector3 playerNodeVelocity = playerNode.velocity;
		playerNodeVelocity.z = sqrtf(-2 * kGravityAcceleration * kJumpHeight);
		[playerNode setVelocity:playerNodeVelocity];
	}
	
	if (theEvent.keyCode == 53) [self setGameLoopRunning:!gameLoopRunning];
}

- (void)keyUp:(NSEvent *)theEvent {
	
	SCNVector4 movement = playerNode.movement;
	if (theEvent.keyCode == 126 || theEvent.keyCode == 13) movement.x = 0;
	if (theEvent.keyCode == 123 || theEvent.keyCode == 0) movement.y = 0;
	if (theEvent.keyCode == 125 || theEvent.keyCode == 1) movement.z = 0;
	if (theEvent.keyCode == 124 || theEvent.keyCode == 2) movement.w = 0;
	[playerNode setMovement:movement];
}

- (void)mouseMoved:(NSEvent *)theEvent {
	if (gameLoopRunning) [playerNode rotateByAmount:CGSizeMake(DEG_TO_RAD(-theEvent.deltaX / 10000), DEG_TO_RAD(-theEvent.deltaY / 10000))];
}

- (void)mouseDown:(NSEvent *)theEvent {
	[self setGameLoopRunning:YES];
	
	[hitTestResult.node removeFromParentNode];
	[self setHitTestResult:nil];
}

- (void)rightMouseDown:(NSEvent *)theEvent {
	
	// TODO: New a more concrete way of determining new block location.
	// Just because a coordinate is exactly 0.5, doesn't mean it's the correct face.
	
	SCNVector3 newNodePosition = hitTestResult.node.position;
	SCNVector3 localCoordinates = hitTestResult.localCoordinates;
	
	if (localCoordinates.x == 0.5) newNodePosition.x += 1;
	else if (localCoordinates.x == -0.5) newNodePosition.x -= 1;
	if (localCoordinates.y == 0.5) newNodePosition.y += 1;
	else if (localCoordinates.y == -0.5) newNodePosition.y -= 1;
	if (localCoordinates.z == 0.5) newNodePosition.z += 1;
	else if (localCoordinates.z == -0.5) newNodePosition.z -= 1;
	
	[self addNodeAtPosition:newNodePosition type:BlockNodeTypeStone];
}

#pragma mark - Memory Management
- (void)dealloc {
	[hitTestResult release];
	CVDisplayLinkRelease(displayLinkRef);
	[super dealloc];
}

@end
