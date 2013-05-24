
#import "cocos2d.h"

/**
 * Delegate for the PanZoomNode. Contains optional methods that can be implemented in order
 * to receive data for user interactions.
 **/
@protocol PanZoomNodeDelegate <NSObject>
@optional

/**
 * Callback for when the user has tapped the given node at the given position.
 **/
- (void) node:(CCNode *)node tappedAt:(CGPoint)pos;

@end


/**
 * Node that performs panning and scrolling of a child node. To use
 * this node initialize it and set the node property to a CCNode that should
 * be pannable and zoomable.
 **/
@interface PanZoomNode : CCNode <CCTargetedTouchDelegate>

// the node that is panned and zoomed
@property (nonatomic, strong) CCNode * node;

// minimum scale for the node. The default is 1.0f
@property (nonatomic, assign) float minScale;

// maximum scale for the node. If both the min and max scales are 1.0f then pinch zooming is disabled. The default is 1.0f
@property (nonatomic, assign) float maxScale;

// friction value for the kinetic scrolling after panning. Applied to the scrolling velocity each tick to reduce the panning
// speed. Sane values are 0 <= friction < 1.0. Default: 0.8
@property (nonatomic, assign) float friction;

// maximum distance a touch can move for it to still be considered a tap. Default: 20 px
@property (nonatomic, assign) float maxTapDistance;

// maximum duration for a touch to still be considered a tap. Default 0.2s
@property (nonatomic, assign) NSTimeInterval maxTapTime;

// optional delegate
@property (nonatomic, assign) id<PanZoomNodeDelegate> delegate;

/**
 * Centers the view on the given pos. Takes scaling into account. If the point is too close to an edge for it to
 * be exactly in the center the node is panned as much as possible.
 **/
- (void) centerOn:(CGPoint)pos;

@end
