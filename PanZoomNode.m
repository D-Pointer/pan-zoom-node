
#import "CGPointExtension.h"
#import "CCDirector.h"
#import "PanZoomNode.h"

@interface PanZoomNode ()

@property (nonatomic, strong) UIPinchGestureRecognizer * pinchRecognizer;
@property (nonatomic, strong) UIPanGestureRecognizer *   panRecognizer;
@property (nonatomic, strong) UITapGestureRecognizer *   tapRecognizer;
@property (nonatomic, assign) CGPoint                    lastPanPosition;
@property (nonatomic, assign) float                      lastScale;
@property (nonatomic, assign) CGPoint                    scrollOffset;

// inertia speed in points per second for when a panning ends
@property (nonatomic, assign) CGPoint                    velocity;

@end

@implementation PanZoomNode

- (id)init {
    self = [super init];
    if (self) {
        self.delegate = nil;

        // no scrolling offset yet
        self.scrollOffset = ccp( 0, 0 );

        self.contentSize = CGSizeMake( 1024, 768 );

        // sane default scales
        self.minScale = 1.0f;
        self.maxScale = 1.0f;
        self.friction = 0.8f;
        
        // pinch recognizer
        self.pinchRecognizer = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(handlePinch:)];
        self.pinchRecognizer.delegate = self;
        [[[CCDirector sharedDirector] view] addGestureRecognizer:self.pinchRecognizer];

        // tap recognizer
        self.tapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
        self.tapRecognizer.delegate = self;
        [[[CCDirector sharedDirector] view] addGestureRecognizer:self.tapRecognizer];
        
        // pan recognizer
        self.panRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        self.panRecognizer.delegate = self;
        [[[CCDirector sharedDirector] view] addGestureRecognizer:self.panRecognizer];
    }

    return self;
}


- (void) setNode:(CCNode *)node {
    // any old node?
    if ( _node ) {
        [_node removeFromParentAndCleanup:YES];
        _node = nil;
    }

    _node = node;
    _node.anchorPoint = ccp(0,0);

    if ( _node ) {
        [self addChild:_node];

        // enable the recognizers
        self.panRecognizer.enabled = YES;
        self.pinchRecognizer.enabled = YES;
        self.tapRecognizer.enabled = YES;
    }
    else {
        // no node, so nothing to pan/pinch etc either
        self.panRecognizer.enabled = NO;
        self.pinchRecognizer.enabled = NO;
        self.tapRecognizer.enabled = NO;
    }
}


- (void) centerOn:(CGPoint)pos {
    // first convert the point to match the node's scale
    CGPoint scaledPos = ccpMult( pos, self.node.scale );

    float width  = self.boundingBox.size.width;
    float height = self.boundingBox.size.height;

    // new scroll offsets for the node
    float scrollX = width / 2- scaledPos.x;
    float scrollY = height / 2 - scaledPos.y;

    // peform the panning
    [self panTo:scrollX y:scrollY];
}


- (void) handlePinch:(UIPinchGestureRecognizer *)recognizer {
    if ( recognizer.state == UIGestureRecognizerStateBegan || recognizer.state == UIGestureRecognizerStateEnded ) {
        self.lastScale = 1.0f;
    }
    else {
        // basic scaling
        CGFloat scale = 1.0f - (self.lastScale - recognizer.scale);
        scale = self.node.scale * scale;

        // keep the scale inside the min and max values
        self.node.scale = clampf( scale, self.minScale, self.maxScale );
        self.lastScale = recognizer.scale;

        float nodeWidth = self.node.boundingBox.size.width;
        float nodeHeight = self.node.boundingBox.size.height;

        // keep the scrolling offset within limits
        float x = MIN( MAX( self.boundingBox.size.width - nodeWidth, self.scrollOffset.x ), 0 );
        float y = MIN( MAX( self.boundingBox.size.height - nodeHeight, self.scrollOffset.y ), 0 );

        // position the node
        self.scrollOffset = ccp( x, y );
        self.node.position = self.scrollOffset;
    }

    // stop all panning immediately
    [self unscheduleUpdate];
}


- (void) handlePan:(UIPanGestureRecognizer *)recognizer {
    CGPoint pos = [[CCDirector sharedDirector] convertToGL:[recognizer locationInView:[[CCDirector sharedDirector] view]]];

    // did we start a panning now?
    CGPoint delta = ccpSub( pos, self.lastPanPosition );

    float x = self.scrollOffset.x + delta.x;
    float y = self.scrollOffset.y + delta.y;

    [self panTo:x y:y];
    
    self.lastPanPosition = pos;

    // if the panning ended now then continue panning through inertia for a while
    if ( recognizer.state == UIGestureRecognizerStateEnded ) {
        self.velocity = [[CCDirector sharedDirector] convertToGL:[recognizer velocityInView:[[CCDirector sharedDirector] view]]];

        // unschedule any previous update() and reschedule a new
        [self unscheduleUpdate];
        [self scheduleUpdate];
    }

}


- (void) handleTap:(UITapGestureRecognizer *)recognizer {
    CGPoint pos = [[CCDirector sharedDirector] convertToGL:[recognizer locationInView:[[CCDirector sharedDirector] view]]];

    // add the scrolling offset
    pos = ccpAdd( pos, ccpNeg(self.scrollOffset) );

    // and scale based on the node scale
    pos = ccpMult( pos, 1 / self.node.scale );
    
    if ( self.delegate ) {
        [self.delegate node:self.node tappedAt:pos];
    }

    // stop all panning immediately
    [self unscheduleUpdate];
}


- (void) panTo:(float)x y:(float)y {
    float nodeWidth = self.node.boundingBox.size.width;
    float nodeHeight = self.node.boundingBox.size.height;

    // keep the scrolling offset within limits
    x = MIN( MAX( self.boundingBox.size.width - nodeWidth, x ), 0 );
    y = MIN( MAX( self.boundingBox.size.height - nodeHeight, y ), 0 );

    // position the node
    self.scrollOffset = ccp( x, y );
    self.node.position = self.scrollOffset;
}


- (void) update:(ccTime)delta {
    // scale the speed with friction
    self.velocity = ccpMult( self.velocity, self.friction );

    // when the speed is slow enough we stop
    if ( self.velocity.x < 1 || self.velocity.y < 1 ) {
        // stop panning
        [self unscheduleUpdate];
        return;
    }

    // where should we pan
    float x = self.scrollOffset.x + self.velocity.x * delta;
    float y = self.scrollOffset.y + self.velocity.y * delta;

    CGPoint lastScrollOffset = self.scrollOffset;

    // perform the panning
    [self panTo:x y:y];

    // did we actually scroll anywhere?
    if ( ccpDistance( lastScrollOffset, self.scrollOffset ) < 1.0f ) {
        // nope, no need to update anymore
        [self unscheduleUpdate];
    }
}


#pragma mark - Gesture Recognizer Delegate

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    // set up some start values of the recohnizer is starting
    if ( gestureRecognizer == self.panRecognizer ) {
        self.lastPanPosition = [[CCDirector sharedDirector] convertToGL:[self.panRecognizer locationInView:[[CCDirector sharedDirector] view]]];
    }
    else if ( gestureRecognizer == self.pinchRecognizer ) {
        self.lastScale = 1.0f;
    }
    
    return YES;
}

@end
