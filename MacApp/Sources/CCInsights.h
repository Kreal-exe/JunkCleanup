// "Also on this disk": space JunkCleanup will not touch, but the user might want to know about.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, CCInsightAction) { CCInsightActionNone, CCInsightActionCopyCommand, CCInsightActionOpenURL };

@interface CCInsight : NSObject
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *symbol;
@property (nonatomic) long long bytes;
@property (nonatomic) CCInsightAction action;
/// The command to copy or the URL to open.
@property (nonatomic, copy, nullable) NSString *payload;
/// Extra values for the detail text after the size ({1}, {2}…).
@property (nonatomic, copy) NSArray<NSString *> *extra;
@property (nonatomic, readonly) NSString *titleKey;
@property (nonatomic, readonly) NSString *detailKey;
@end

@interface CCInsights : NSObject
/// Slow (sizes folders, asks tmutil); call off the main thread. trashTargetEnabled hides the Trash insight.
+ (NSArray<CCInsight *> *)scanWithTrashTargetEnabled:(BOOL)trashTargetEnabled;
@end

NS_ASSUME_NONNULL_END
