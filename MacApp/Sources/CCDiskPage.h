// The Disk page of the Linux app's Views/DiskView.axaml: what fills the disk, band by band and folder by folder, and
// what can go. CCDiskModel holds the analysis (DiskViewModel.cs); CCDiskPage shows it.
#import <Cocoa/Cocoa.h>
#import "CCEngine.h"
#import "CCPages.h"

NS_ASSUME_NONNULL_BEGIN

@interface CCDiskModel : NSObject
@property (class, nonatomic, readonly) CCDiskModel *shared;
@property (nonatomic, readonly) BOOL analyzing;
@property (nonatomic, strong, readonly, nullable) CCSpaceReport *report;
@property (nonatomic, readonly) NSString *statusText;

/// The disks to choose from; the picker shows only when there is more than one.
@property (nonatomic, readonly) NSArray<CCVolume *> *volumes;
@property (nonatomic, strong, readonly, nullable) CCVolume *selectedVolume;
/// Another disk: the old map goes, the new one is measured (after the running analysis stops).
- (void)selectVolume:(CCVolume *)volume;
/// For the hidden --drive switch: picks a disk by name or mount point, measuring nothing yet.
- (void)preselectVolume:(NSString *)nameOrPath;

/// The band the list is narrowed to, or -1 for every band.
@property (nonatomic, readonly) NSInteger filter;
/// A band of the bar or the legend: show only its items; the same band again shows all.
- (void)pickSegment:(NSInteger)segment;
- (void)clearFilter;


- (void)toggleAnalyze;
- (void)analyze;
- (void)cancel;

/// Every Safe part outside the cleaner's targets (those are cleaned from the Targets page).
- (NSArray<CCSpaceEntry *> *)safeParts;
- (long long)safeBytes;
/// What can go without a second thought inside one item: the item when it is Safe, else its Safe parts.
+ (NSArray<CCSpaceEntry *> *)safePartsOf:(CCSpaceEntry *)entry;

/// Asks, then removes every Safe part.
- (void)removeSafe;
/// Into the Trash or permanently, per the settings; the answer arrives on the main thread.
- (void)remove:(CCSpaceEntry *)entry completion:(nullable void (^)(BOOL ok))completion;
- (BOOL)isBusy:(CCSpaceEntry *)entry;
- (void)copyCommand:(CCSpaceEntry *)entry;
@end

@interface CCDiskPage : CCPageView
/// For --capture: opens the first item with safe parts and scrolls it into view.
- (void)revealPartsForCapture;
@end

NS_ASSUME_NONNULL_END
