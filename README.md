pan-zoom-node
=============

Cocos2D node for panning and zooming a larger node. It currently allows you to set a CCNode that will be panned 
and zoomed using normal swipe and pinch gestures. You can set a maximum and minimum scale to control how much the user
can zoom.

Panning has a basic form of inertia, meaning the panning will continue for a short while after the user releases
his/her finger. This can be controller using the `friction` property.


# Usage

Usage is quite simple:

```
// implement the PanZoomNodeDelegate to get notifications
@interface GameNode : CCNode <PanZoomNodeDelegate>

@property (nonatomic, strong) PanZoomNode * panZoomNode;
...

- (id) init {
	if( (self=[super init]) ) {
    self.panZoomNode = [[PanZoomNode alloc] init];
  
    // we're a delegate 
    self.panZoomNode.delegate = self;

    // stop inertia scrolling quite fast
    self.panZoomNode.friction = 0.75;
    
    // position at lower left. this really isn't handled too well yet
  	self.panZoomNode.position =  ccp( 0, 0 );
        
    [self addChild: self.panZoomNode];

    // the thing we pan is in this case a large sprite
    self.panZoomNode.node = [CCSprite spriteWithFile:@"map.png"];
    
    // allow 3x zooming in
    self.panZoomNode.maxScale = 3.0f;
    
    // allow zooming out as much as possible without introducing any "black borders"
  	CGSize ourSize = [[CCDirector sharedDirector] winSize];
    CGSize nodeSize = self.panZoomNode.node.boundingBox.size;
    self.panZoomNode.minScale = MAX( ourSize.width / nodeSize.width, ourSize.height / nodeSize.height );
```

You will receive callbacks to the method `node:tappedAt:`

```
- (void) node:(CCNode *)node tappedAt:(CGPoint)pos {
  CCLOG( @"node tapped at position: %f, %f", pos.x, pos.y );
}
```

To center the PanZoomNode on some arbitrary point in the call the `centerOn:` method:
```
  [self.panZoomNode centerOn:ccp(1000, 1000)];
```

That's it, more or less.


# Missing features

* Allow for smooth scrolling when centering on a point.
* Allow for programmatic zooming to a certain zoom level.
* Better handling of node anchor point and position (now it's a bit of a mess).

# License
This little thing can be used under the MIT license.
