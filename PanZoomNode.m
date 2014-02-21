
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

@property (nonatomic, assign) float              lastScale;
@property (nonatomic, readwrite, assign) CGPoint panOffset;

// inertia speed in points per second for when a panning ends
@property (nonatomic, assign) CGPoint            velocity;

@property (nonatomic, assign) BOOL               dragging;

@end


@implementation PanZoomNode

- (id)init {
    self = [super init];
    if (self) {
        self.delegate = nil;

        // no scrolling offset yet
        self.panOffset = ccp( 0, 0 );

        // assume we cover the entire screen
        self.contentSize = [[CCDirector sharedDirector] winSize];

        // not dragging
        self.dragging = NO;

        // sane default scales
        self.minScale = 1.0f;
        self.maxScale = 1.0f;
        self.friction = 0.8;

        // max time and distance for a tap to be a tap and not a pan
        self.maxTapDistance = 20;
        self.maxTapTime = 0.2;
        self.maxLongPressTime = 1.0;

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

    CGPoint pos = ccpMult( ccpNeg( self.panOffset ), 1 / self.node.scale );

    CGFloat width = self.boundingBox.size.width * ( 1 / self.node.scale );
    CGFloat height = self.boundingBox.size.height * ( 1 / self.node.scale );

    return CGRectMake( pos.x, pos.y, width, height );
}


- (void) centerOn:(CGPoint)pos {
    NSAssert( self.node, @"no node set" );

    //CCLOG( @"centering on: %.1f, %.1f", pos.x, pos.y );

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
    self.dragging = NO;
}


- (void) panTo:(float)x y:(float)y {
    NSAssert( self.node, @"no node set" );

    float nodeWidth = self.node.boundingBox.size.width;
    float nodeHeight = self.node.boundingBox.size.height;

    // keep the scrolling offset within limits
    x = MIN( MAX( self.boundingBox.size.width - nodeWidth, x ), 0 );
    y = MIN( MAX( self.boundingBox.size.height - nodeHeight, y ), 0 );

    // position the node
    self.panOffset = ccp( x, y );
    self.node.position = self.panOffset;

    if ( self.delegate && [self.delegate respondsToSelector:@selector(pannedNode:)] ) {
        // inform the delegate
        [self.delegate pannedNode:self.node];
    }
}


- (void) update:(ccTime)delta {
    // scale the speed with friction
    self.velocity = ccpMult( self.velocity, self.friction );

    //CCLOG( @"velocity: %.0f, %.0f, friction: %.2f", self.velocity.x, self.velocity.y, self.friction );

    // when the speed is slow enough we stop
    if ( fabsf( self.velocity.x ) < 1 && fabsf( self.velocity.y ) < 1 ) {
        // stop panning
        //CCLOG( @"velocity done" );
        [self unscheduleUpdate];
        return;
    }

    // where should we pan
    float x = self.panOffset.x + self.velocity.x * delta;
    float y = self.panOffset.y + self.velocity.y * delta;

    CGPoint lastpanOffset = self.panOffset;

    // perform the panning
    [self panTo:x y:y];

    // did we actually scroll anywhere?
    float scrolledX = fabsf( lastpanOffset.x - self.panOffset.x );
    float scrolledY = fabsf( lastpanOffset.y - self.panOffset.y );
    //CCLOG( @"scrolled: %.2f, %.2f", scrolledX, scrolledY );

    if ( scrolledX < 0.2f && scrolledY < 0.2f ) {
        // nope, no need to update anymore
        //CCLOG( @"no scrolling" );
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
        //CCLOG( @"already two touches, ignoring extra touches" );
        return NO;
    }

    // are we dragging?
    if ( self.dragging ) {
        CCLOG( @"dragging, ignoring new touch" );
        return NO;
    }

    CCLOG( @"touch count: %d", event.allTouches.count );

    for ( UITouch * tmpTouch in event.allTouches ) {
        CGPoint pos = [[CCDirector sharedDirector] convertToGL:[tmpTouch locationInView:[[CCDirector sharedDirector] view]]];

        // first touch already taken? when we pinch we will get all the old touches too in allTouches, so we need
        // to avoid using the same touch for 1 and 2
        if ( self.touch1 == tmpTouch ) {
            // this is already the first touch, we're done with it
            //CCLOG( @"same first touch" );
        }

        // first touch free?
        else if ( self.touch1 == nil ) {
            //CCLOG( @"got touch 1" );
            self.touch1 = tmpTouch;
            self.timestamp = tmpTouch.timestamp;
            self.lastTimestamp = tmpTouch.timestamp;
            
            // save the starting position
            self.touch1StartPos = pos;

            // if we only have one touch then we may be starting a drag
            if ( event.allTouches.count == 1 ) {
                CCLOG( @"possible drag start" );
                if ( self.delegate && [self.delegate respondsToSelector:@selector(shouldStartDragForNode:atPos:)] ) {
                    // pressed pos
                    CGPoint pressedPos = ccpAdd( ccpNeg( self.panOffset ), pos );

                    // adjust by scale
                    pressedPos = ccpMult( pressedPos, 1 / self.node.scale );
                    self.dragging = [self.delegate shouldStartDragForNode:self.node atPos:pressedPos];
                }
                else {
                    self.dragging = NO;
                }
            }
        }
        else if ( self.touch2 == nil ) {
            //CCLOG( @"got touch 2" );
            self.touch2 = tmpTouch;

            CGPoint touch1Pos = [[CCDirector sharedDirector] convertToGL:[self.touch1 locationInView:[[CCDirector sharedDirector] view]]];

            // now we're pinching, save the starting distance between the touches
            self.startPinchDistance = ccpDistance( touch1Pos, pos );

            //CCLOG( @"start pinch, distance: %.0f", self.startPinchDistance );
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

        // are we dragging?
        if ( self.dragging ) {
            CCLOG( @"dragging: %.0f, %.0f", newPos.x, newPos.y );
            if ( self.delegate && [self.delegate respondsToSelector:@selector(node:draggedTo:)] ) {
                // pressed pos
                CGPoint pressedPos = ccpAdd( ccpNeg( self.panOffset ), newPos );

                // adjust by scale
                pressedPos = ccpMult( pressedPos, 1 / self.node.scale );

                // call the delegate
                self.dragging = [self.delegate node:self.node draggedTo:pressedPos];
            }
            else {
                self.dragging = NO;
            }
        }
        else {
            // no drag, do a normal pan
            // get the delta position
            CGPoint delta = ccpSub( newPos, oldPos );
            //CCLOG( @"pan delta: %.0f, %.0f", delta.x, delta.y );

            float x = self.panOffset.x + delta.x;
            float y = self.panOffset.y + delta.y;

            [self panTo:x y:y];
        }

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

        // check for NaN or infinity. this is really a bug in the touch handling and should probably be asserted out of here?
        if ( isnan( scale ) || isinf( scale ) ) {
            // oops
            CCLOG( @"isnan or isinf...");
            return;
        }
        
        //CCLOG( @"pinch distance: %.0f, scale %.2f", newDistance, scale );

        // get the current centerpoint of the visible area. this is where we want to center the node after the scale
        CGRect rect = self.visibleRect;
        CGPoint center = ccp( rect.origin.x + rect.size.width / 2, rect.origin.y + rect.size.height / 2 );

        // keep the scale inside the min and max values
        self.node.scale = clampf( scale, self.minScale, self.maxScale );
        self.lastScale = newScale;

        // perform the centering
        [self centerOn:center];

        if ( self.delegate && [self.delegate respondsToSelector:@selector(node:scaledTo:)] ) {
            // inform the delegate
            [self.delegate node:self.node scaledTo:self.node.scale];
        }
    }
}


- (void) ccTouchEnded:(UITouch *)touch withEvent:(UIEvent *)event {
    // only one touch?
    if ( self.touch1 != nil && self.touch2 == nil ) {
        // one touch only, so this was a tap, drag or a pan
        if ( self.dragging ) {
            CCLOG( @"dragging ended" );
            if ( self.delegate && [self.delegate respondsToSelector:@selector(dragEndedForNode:)] ) {
                [self.delegate dragEndedForNode:self.node];
            }

            self.dragging = NO;
        }

        // NOTE: this else is commented out so that short drags (in time) are still considered as taps
        //else {
            // a tap or a pan
            NSTimeInterval elapsed = event.timestamp - self.timestamp;
            //CCLOG( @"single touch ended, elapsed time: %.2f", elapsed );

            CGPoint pos = [[CCDirector sharedDirector] convertToGL:[touch locationInView:[[CCDirector sharedDirector] view]]];

            // short and close enough for a tap? we check the distance in our coordinate system and don't care for any scaling,
            // we just want the raw distance on the screen
            if ( ccpDistance( pos, self.touch1StartPos ) < self.maxTapDistance ) {
                // final position in the node we scroll
                CGPoint nodePos = ccpAdd( ccpNeg( self.panOffset ), pos );

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
                else if ( elapsed >= self.maxLongPressTime ) {
                    CCLOG( @"long press" );
                    if ( self.delegate && [self.delegate respondsToSelector:@selector(node:longPressesAt:)] ) {
                        // inform the delegate
                        [self.delegate node:self.node longPressesAt:nodePos];
                    }
                }
            }
            else {
                // pan ended

                // the time it took to move that velocity distance
                NSTimeInterval time = touch.timestamp - self.lastTimestamp;

                // calculate a velocity
                CGPoint oldPos = [[CCDirector sharedDirector] convertToGL:[touch previousLocationInView:[[CCDirector sharedDirector] view]]];
                self.velocity = ccpMult( ccpSub( pos, oldPos ), sqrtf( 1 / time ) );

                //CCLOG( @"pan ended, time: %.3f, velocity: %.0f, %.0f", time, self.velocity.x, self.velocity.y );
                
                // unschedule any previous update() and reschedule a new
                [self unscheduleUpdate];
                [self scheduleUpdate];
            }
        //}
    }

    [self resetTouches];
}


- (void) ccTouchCancelled:(UITouch *)touch withEvent:(UIEvent *)event {
    [self resetTouches];
}


@end
