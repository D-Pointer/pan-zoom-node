
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

@property (nonatomic, assign) float          lastScale;
@property (nonatomic, assign) CGPoint        scrollOffset;

// inertia speed in points per second for when a panning ends
@property (nonatomic, assign) CGPoint        velocity;

@end


@implementation PanZoomNode

- (id)init {
    self = [super init];
    if (self) {
        self.delegate = nil;

        // no scrolling offset yet
        self.scrollOffset = ccp( 0, 0 );

        // assume we cover the entire screen
        self.contentSize = [[CCDirector sharedDirector] winSize];

        //
        // sane default scales
        self.minScale = 1.0f;
        self.maxScale = 1.0f;
        self.friction = 0.8;

        // max time and distance for a tap to be a tap and not a pan
        self.maxTapDistance = 20;
        self.maxTapTime = 0.2;
        self.maxLongPressime = 1.0;

        // default touch priority
        self.touchPriority = 0;
        
        [self resetTouches];
    }

    return self;
}


- (void)onEnter {
    [[[CCDirector sharedDirector] touchDispatcher] addTargetedDelegate:self priority:self.touchPriority swallowsTouches:YES];
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


- (CGRect) visibleRect {
    // no node yet?
    if ( ! self.node ) {
        return CGRectNull;
    }

    CGPoint pos = ccpMult( ccpNeg( self.scrollOffset ), 1 / self.node.scale );

    CGFloat width = self.boundingBox.size.width * ( 1 / self.node.scale );
    CGFloat height = self.boundingBox.size.height * ( 1 / self.node.scale );

    return CGRectMake( pos.x, pos.y, width, height );
}


- (void) centerOn:(CGPoint)pos {
    NSAssert( self.node, @"no node set" );

    CCLOG( @"centering on: %.1f, %.1f", pos.x, pos.y );

    // first convert the point to match the node's scale
    CGPoint scaledPos = ccpMult( pos, self.node.scale );

    float width  = self.boundingBox.size.width;
    float height = self.boundingBox.size.height;

    // new scroll offsets for the node
    float scrollX = width / 2 - scaledPos.x;
    float scrollY = height / 2 - scaledPos.y;

    // peform the panning
    [self panTo:scrollX y:scrollY];
}


- (void) resetTouches {
    self.touch1 = nil;
    self.touch2 = nil;
    self.timestamp = 0;
}


- (void) panTo:(float)x y:(float)y {
    NSAssert( self.node, @"no node set" );

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

    if ( scrolledX < 0.2f && scrolledY < 0.2f ) {
        // nope, no need to update anymore
        CCLOG( @"no scrolling" );
        [self unscheduleUpdate];
    }
}


// ******************************************************************************************************************************
#pragma mark - Touch handling

- (BOOL)ccTouchBegan:(UITouch *)touch withEvent:(UIEvent *)event {
    // if we have no node then we don't do anything
    if ( self.node == nil ) {
        CCLOG( @"no node has been set, ignoring touch" );
        return NO;
    }

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

        //CCLOG( @"pinch distance: %.0f, scale %.2f", newDistance, scale );

        // get the current centerpoint of the visible area. this is where we want to center the node after the scale
        CGRect rect = self.visibleRect;
        CGPoint center = ccp( rect.origin.x + rect.size.width / 2, rect.origin.y + rect.size.height / 2 );

        // keep the scale inside the min and max values
        self.node.scale = clampf( scale, self.minScale, self.maxScale );
        self.lastScale = newScale;

        // perform the centering
        [self centerOn:center];
    }
}


- (void) ccTouchEnded:(UITouch *)touch withEvent:(UIEvent *)event {
    // only one touch?
    if ( self.touch1 != nil && self.touch2 == nil ) {
        // one touch only, so this was a tap or a pan
        NSTimeInterval elapsed = event.timestamp - self.timestamp;
        //CCLOG( @"single touch ended, elapsed time: %.2f", elapsed );

        CGPoint pos = [[CCDirector sharedDirector] convertToGL:[touch locationInView:[[CCDirector sharedDirector] view]]];
        
        // short and close enough for a tap? we check the distance in our coordinate system and don't care for any scaling,
        // we just want the raw distance on the screen
        if ( ccpDistance( pos, self.touch1StartPos ) < self.maxTapDistance ) {
            // final position in the node we scroll
            CGPoint nodePos = ccpAdd( ccpNeg( self.scrollOffset ), pos );

            // adjust by scale
            nodePos = ccpMult( nodePos, 1 / self.node.scale );

            // short enough for a tap?
            if ( elapsed < self.maxTapTime ) {
                CCLOG( @"tap" );
                if ( self.delegate && [self.delegate respondsToSelector:@selector(node:tappedAt:)] ) {
                    // inform the delegate
                    [self.delegate node:self.node tappedAt:nodePos];
                }
            }

            // long enough for a long press?
            else if ( elapsed >= self.maxLongPressime ) {
                CCLOG( @"long press" );
                if ( self.delegate && [self.delegate respondsToSelector:@selector(node:longPressesAt:)] ) {
                    // inform the delegate
                    [self.delegate node:self.node longPressesAt:nodePos];
                }
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


@end
