
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
    _node = node;
    _node.anchorPoint = ccp(0,0);
    [self addChild:_node];
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
}


- (void) handlePan:(UIPanGestureRecognizer *)recognizer {
    CGPoint pos = [[CCDirector sharedDirector] convertToGL:[recognizer locationInView:[[CCDirector sharedDirector] view]]];

    // did we start a panning now?
    CGPoint delta = ccpSub( pos, self.lastPanPosition );

    float x = self.scrollOffset.x + delta.x;
    float y = self.scrollOffset.y + delta.y;

    [self panTo:x y:y];
    
    self.lastPanPosition = pos;

    if ( recognizer.state == UIGestureRecognizerStateEnded ) {
        self.velocity = [[CCDirector sharedDirector] convertToGL:[recognizer velocityInView:[[CCDirector sharedDirector] view]]];
        CCLOG( @"inertia: %.1f, %.1f", self.velocity.x, self.velocity.y );
        [self unscheduleUpdate];
        [self scheduleUpdate];
    }

}


- (void) handleTap:(UITapGestureRecognizer *)recognizer {
    CGPoint pos = [[CCDirector sharedDirector] convertToGL:[recognizer locationInView:[[CCDirector sharedDirector] view]]];

    // add the scrolling offset
    pos = ccpAdd( pos, ccpNeg(self.scrollOffset) );
    
    if ( self.delegate ) {
        [self.delegate node:self.node tappedAt:pos];
    }
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
    CCLOG( @"start: %.1f, %.1f", self.velocity.x, self.velocity.y );

    // scale the speed with friction
    self.velocity = ccpMult( self.velocity, self.friction );
    CCLOG( @"scaled: %.1f, %.1f", self.velocity.x, self.velocity.y );

    if ( self.velocity.x < 1 && self.velocity.y < 1 ) {
        // stop panning
        [self unscheduleUpdate];
        return;
    }

    // where should we pan
    float x = self.scrollOffset.x + self.velocity.x * delta;
    float y = self.scrollOffset.y + self.velocity.y * delta;

    [self panTo:x y:y];
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

/*
#pragma mark - Touch One By One Delegate

- (BOOL)ccTouchBegan:(UITouch *)touch withEvent:(UIEvent *)event {
    return NO;
    
    for ( UITouch * tmpTouch in event.allTouches ) {
        if ( self.firstTouch == nil ) {
            self.firstTouch = tmpTouch;
            self.firstPos = [[CCDirector sharedDirector] convertToGL:[tmpTouch locationInView:[tmpTouch view]]];
            self.firstTime = [NSDate timeIntervalSinceReferenceDate];

        }
        else if ( self.secondTouch == nil ) {
            self.secondTouch = tmpTouch;
            self.secondPos = [[CCDirector sharedDirector] convertToGL:[tmpTouch locationInView:[tmpTouch view]]];
            self.secondTime = [NSDate timeIntervalSinceReferenceDate];
        }
    }

    CCLOG(@"touch count: %d", event.allTouches.count );
    return YES;
}

- (void)ccTouchMoved:(UITouch *)touch withEvent:(UIEvent *)event {
    if ( self.firstTouch && self.secondTouch ) {
        // pinching
        CGPoint firstCurrent   = [[CCDirector sharedDirector] convertToGL:[self.firstTouch locationInView:[self.firstTouch view]]];
        CGPoint firstPrevious  = [[CCDirector sharedDirector] convertToGL:[self.firstTouch previousLocationInView:[self.firstTouch view]]];
        CGPoint secondCurrent  = [[CCDirector sharedDirector] convertToGL:[self.secondTouch locationInView:[self.secondTouch view]]];
        CGPoint secondPrevious = [[CCDirector sharedDirector] convertToGL:[self.secondTouch previousLocationInView:[self.secondTouch view]]];

        // starting distance
        float startDistance = ccpDistance( self.firstPos, self.secondPos );
        float currentDistance = ccpDistance( firstCurrent, secondCurrent );
        float previousDistance = ccpDistance( firstPrevious, secondPrevious );
        float scale = self.node.scale * currentDistance / previousDistance;

        // keep the scale inside the min and max values
        scale = clampf( scale, self.minScale, self.maxScale );
        self.node.scale = scale;

        CCLOG( @"pinching: previous: %.1f, current: %.1f, scale: %.1f", previousDistance, currentDistance, scale );
    }
    else if ( self.firstTouch ) {
        // panning. first see how much we've panned since the last time this was called
        CGPoint current = [[CCDirector sharedDirector] convertToGL:[touch locationInView:[self.firstTouch view]]];
        CGPoint previous = [[CCDirector sharedDirector] convertToGL:[touch previousLocationInView:[self.firstTouch view]]];
        CGPoint delta = ccpSub(current, previous );

        float x = self.scrollOffset.x + delta.x;
        float y = self.scrollOffset.y + delta.y;

        // keep the scrolling offset within limits
        x = MIN( MAX( self.boundingBox.size.width - self.node.boundingBox.size.width, x ), 0 );
        y = MIN( MAX( self.boundingBox.size.height - self.node.boundingBox.size.height, y ), 0 );

        // position the node
        self.scrollOffset = ccp( x, y );
        self.node.position = self.scrollOffset;

        CCLOG(@"panning: current %.1f, %.1f, previous %.1f, %.1f, delta: %.1f %.1f", current.x, current.y, previous.x, previous.y, delta.x, delta.y);
    }
    else {
        // wtf?
        NSAssert( NO, @"no touches?");
    }
}


- (void)ccTouchEnded:(UITouch *)touch withEvent:(UIEvent *)event {
    CCLOG(@"touch count: %d", event.allTouches.count );

    for ( UITouch * tmpTouch in event.allTouches ) {

        if ( tmpTouch == self.secondTouch ) {
            self.secondTouch = nil;
        }
        else if ( tmpTouch == self.firstTouch ) {
            // could it have been a click?
            if ( self.secondTouch == nil ) {
                // how long since touch started?
                NSTimeInterval touchLength = [NSDate timeIntervalSinceReferenceDate] - self.firstTime;

                // how far from the start pos?
                float distance = ccpDistance( self.firstPos, [[CCDirector sharedDirector] convertToGL:[tmpTouch locationInView:[self.firstTouch view]]] );

                CCLOG( @"touch time: %.2f, length: %.0f", touchLength, distance );
                if ( distance  < 20.0f && touchLength < 0.2f ) {
                    CCLOG( @"tap!" );
                }
            }

            self.firstTouch = self.secondTouch;
            self.secondTouch = nil;
        }
    }
}


- (void)ccTouchCancelled:(UITouch *)touch withEvent:(UIEvent *)event {
    CCLOG(@"in");
    self.firstTouch = nil;
    self.secondTouch = nil;
}
*/

@end
