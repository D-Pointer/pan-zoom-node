
#import "CGPointExtension.h"
#import "CCDirector.h"
#import "PanZoomNode.h"

@interface PanZoomNode ()

@property (nonatomic, strong) UITouch *      touch1;
@property (nonatomic, strong) UITouch *      touch2;
@property (nonatomic, assign) NSTimeInterval timestamp;
@property (nonatomic, assign) NSTimeInterval lastTimestamp;
@property (nonatomic, assign) CGPoint        touch1StartPos;

@property (nonatomic, assign) float          startPinchDistance;

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
        self.friction = 0.8;

        // max time and distance for a tap to be a tap and not a pan
        self.maxTapDistance = 20;
        self.maxTapTime = 0.2;
        
        [self resetTouches];
    }

    return self;
}


- (void)onEnter {
    [[[CCDirector sharedDirector] touchDispatcher] addTargetedDelegate:self priority:0 swallowsTouches:YES];
    [super onEnter];
}


- (void)onExit {
    [[[CCDirector sharedDirector] touchDispatcher] removeDelegate:self];
    [super onExit];
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


// ******************************************************************************************************************************
#pragma mark - Touch handling

- (BOOL)ccTouchBegan:(UITouch *)touch withEvent:(UIEvent *)event {
    // already two touches?
    if ( self.touch1 && self.touch2 ) {
        // we don't care about more touches than two
        CCLOG( @"already two touches, ignoring extra touches" );
        return NO;
    }
    
    for ( UITouch * tmpTouch in event.allTouches ) {
        CGPoint pos = [[CCDirector sharedDirector] convertToGL:[touch locationInView:[[CCDirector sharedDirector] view]]];

        CCLOG( @"pos: %.0f, %.0f", pos.x, pos.y );
        
        // first touch free?
        if ( self.touch1 == nil ) {
            CCLOG( @"got touch 1" );
            self.touch1 = tmpTouch;
            self.timestamp = tmpTouch.timestamp;
            self.lastTimestamp = tmpTouch.timestamp;
            
            // save the starting position
            self.touch1StartPos = pos;
        }
        else if ( self.touch2 == nil ) {
            self.touch2 = tmpTouch;

            // now we're pinching, save the starting distance between the touches
            self.startPinchDistance = ccpDistance([[CCDirector sharedDirector] convertToGL:[self.touch1 locationInView:[[CCDirector sharedDirector] view]]],
                                                  [[CCDirector sharedDirector] convertToGL:[self.touch2 locationInView:[[CCDirector sharedDirector] view]]] );

            CCLOG( @"start pinch, distance: %.0f", self.startPinchDistance );
            self.lastScale = 1.0f;
        }
    }

    // stop any old panning
    [self unscheduleUpdate];

    return YES;
}


- (void) ccTouchMoved:(UITouch *)touch withEvent:(UIEvent *)event {
    // only one touch?
    if ( self.touch1 != nil && self.touch2 == nil ) {
        // panning
        CGPoint newPos = [[CCDirector sharedDirector] convertToGL:[touch locationInView:[[CCDirector sharedDirector] view]]];
        CGPoint oldPos = [[CCDirector sharedDirector] convertToGL:[touch previousLocationInView:[[CCDirector sharedDirector] view]]];

        // delta position
        CGPoint delta = ccpSub( newPos, oldPos );
        CCLOG( @"pan delta: %.0f, %.0f", delta.x, delta.y );

        float x = self.scrollOffset.x + delta.x;
        float y = self.scrollOffset.y + delta.y;

        [self panTo:x y:y];

        // update the timestamp
        self.lastTimestamp = touch.timestamp;
    }

    else {
        // pinch zoom
        float newDistance = ccpDistance([[CCDirector sharedDirector] convertToGL:[self.touch1 locationInView:[[CCDirector sharedDirector] view]]],
                                        [[CCDirector sharedDirector] convertToGL:[self.touch2 locationInView:[[CCDirector sharedDirector] view]]] );

        float newScale = newDistance / self.startPinchDistance;

        CGFloat scale = 1.0f - (self.lastScale - newScale );
        scale = self.node.scale * scale;

        CCLOG( @"pinch distance: %.0f, scale %.2f", newDistance, scale );

        // keep the scale inside the min and max values
        self.node.scale = clampf( scale, self.minScale, self.maxScale );
        self.lastScale = newScale;

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


- (void) ccTouchEnded:(UITouch *)touch withEvent:(UIEvent *)event {
    // only one touch?
    if ( self.touch1 != nil && self.touch2 == nil ) {
        // one touch only, so this was a tap or a pan
        NSTimeInterval elapsed = event.timestamp - self.timestamp;
        CCLOG( @"single touch ended, elapsed time: %.2f", elapsed );

        CGPoint pos = [[CCDirector sharedDirector] convertToGL:[touch locationInView:[[CCDirector sharedDirector] view]]];
        
        // short and close enough for a tap? we check the distance in our coordinate system and don't care for any scaling,
        // we just want the raw distance on the screen
        if ( elapsed < self.maxTapTime && ccpDistance( pos, self.touch1StartPos ) < self.maxTapDistance ) {
            CCLOG( @"tap" );
            if ( self.delegate && [self.delegate respondsToSelector:@selector(node:tappedAt:)] ) {
                // final position in the node we scroll
                CGPoint nodePos = ccpAdd( ccpNeg( self.scrollOffset ), pos );

                // adjust by scale
                nodePos = ccpMult( nodePos, 1 / self.node.scale );

                // inform the delegate
                [self.delegate node:self.node tappedAt:nodePos];
            }
        }
        else {
            // pan ended,

            // the time it took to move that velocity distance
            NSTimeInterval time = touch.timestamp - self.lastTimestamp;

            CCLOG( @"pan ended, time: %.3f", time );
            
            // calculate a velocity
            CGPoint oldPos = [[CCDirector sharedDirector] convertToGL:[touch previousLocationInView:[[CCDirector sharedDirector] view]]];
            self.velocity = ccpMult( ccpSub( pos, oldPos ), sqrtf( 1 / time ) );

            CCLOG( @"pan ended, velocity: %.0f, %.0f", self.velocity.x, self.velocity.y );

            // unschedule any previous update() and reschedule a new
            [self unscheduleUpdate];
            [self scheduleUpdate];
        }
    }

    [self resetTouches];
}


- (void) ccTouchCancelled:(UITouch *)touch withEvent:(UIEvent *)event {
    [self resetTouches];
}


- (void) resetTouches {
    CCLOG( @"in" );
    self.touch1 = nil;
    self.touch2 = nil;
    self.timestamp = 0;
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

    CCLOG( @"velocity: %.0f, %.0f, friction: %.2f", self.velocity.x, self.velocity.y, self.friction );

    // when the speed is slow enough we stop
    if ( fabsf( self.velocity.x ) < 1 && fabsf( self.velocity.y ) < 1 ) {
        // stop panning
        CCLOG( @"velocity done" );
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
    float scrolledX = fabsf( lastScrollOffset.x - self.scrollOffset.x );
    float scrolledY = fabsf( lastScrollOffset.y - self.scrollOffset.y );
    CCLOG( @"scrolled: %.2f, %.2f", scrolledX, scrolledY );

    //float scrollDistance = ccpDistance( lastScrollOffset, self.scrollOffset );
    //if ( scrollDistance < 1.0f ) {
    if ( scrolledX < 0.2f && scrolledY < 0.2f ) {
        // nope, no need to update anymore
        CCLOG( @"no scrolling" );
        [self unscheduleUpdate];
    }
}


/*
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
 //self.velocity = [[CCDirector sharedDirector] convertToGL:[recognizer velocityInView:[[CCDirector sharedDirector] view]]];
 self.velocity = [recognizer velocityInView:[[CCDirector sharedDirector] view]];

 // negate the y component, otherwise we move in the wrong direction
 self.velocity = ccp( self.velocity.x, -self.velocity.y );

 // unschedule any previous update() and reschedule a new
 [self unscheduleUpdate];
 [self scheduleUpdate];
 }

 }


 - (void) handleTap:(UITapGestureRecognizer *)recognizer {
 CCLOG( @"in" );
 CGPoint pos = [[CCDirector sharedDirector] convertToGL:[recognizer locationInView:[[CCDirector sharedDirector] view]]];

 // add the scrolling offset
 pos = ccpAdd( pos, ccpNeg(self.scrollOffset) );

 // and scale based on the node scale
 pos = ccpMult( pos, 1 / self.node.scale );

 if ( self.delegate && [self.delegate respondsToSelector:@selector(node:tappedAt:)]) {
 [self.delegate node:self.node tappedAt:pos];
 }

 // stop all panning immediately
 [self unscheduleUpdate];
 }
 */

#pragma mark - Gesture Recognizer Delegate
/*
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    CGPoint pos = [[CCDirector sharedDirector] convertToGL:[self.panRecognizer locationInView:gestureRecognizer.view]];

    // start looking up
    CCLOG( @"start check for pos: %.1f, %.1f", pos.x, pos.y );

    CCNode * rootNode = self;

    while ( rootNode.parent != nil ) {
        rootNode = rootNode.parent;
    }


    // start looking up
    CCLOG( @"root node: %@, touches: %d", rootNode, [rootNode respondsToSelector:@selector(ccTouchBegan:withEvent:)] );

    return NO;
}


- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    // set up some start values of the recohnizer is starting
    if ( gestureRecognizer == self.panRecognizer ) {
        self.lastPanPosition = [[CCDirector sharedDirector] convertToGL:[self.panRecognizer locationInView:gestureRecognizer.view]];
    }
    else if ( gestureRecognizer == self.pinchRecognizer ) {
        self.lastScale = 1.0f;
    }
    
    return YES;
}
*/
@end
