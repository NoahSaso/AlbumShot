@import AssetsLibrary;
@import Photos;
#include <stdarg.h>

// Delay save to album for SAVE_DELAY seconds so phone has time to add image to camera roll
#define SAVE_DELAY 3

// Get screenshot C method definition
extern "C" UIImage *_UICreateScreenUIImage();

static void saveLatestPhotoToCurrentAppAlbum();
static void moveLatestPhotoToAlbumWithName(NSString *albumName);
static void saveLatestPHAssetToCollection(PHAssetCollection *collection, NSString *albumName);

@interface SBScreenFlash : NSObject
// iOS 7
+ (id)sharedInstance;
- (void)flash;
// iOS 8-10
+ (id)mainScreenFlasher;
- (void)flashWhiteWithCompletion:(id)arg1;
// Mine
+ (id)mySharedInstance;
- (void)flashWhiteNow;
@end

@interface SBApplication : NSObject
- (id)displayName;
@end

@interface UIApplication (AlbumShot)
- (id)_accessibilityFrontMostApplication;
@end

%hook SBScreenFlash

%new +(id)mySharedInstance {
	if([%c(SBScreenFlash) respondsToSelector:@selector(sharedInstance)]) {
		return [self sharedInstance]; // iOS 7
	}
	return [self mainScreenFlasher]; // iOS 8-10
}

%new -(void)flashWhiteNow {
	if([self respondsToSelector:@selector(flash)]) {
		[self flash]; // iOS 7
	}else {
		[self flashWhiteWithCompletion:nil]; // iOS 8-10
	}
}

%end

// iOS 10
%hook SBScreenshotManager

- (void)saveScreenshotsWithCompletion:(id)arg1 {
	%orig;
	saveLatestPhotoToCurrentAppAlbum();
}

%end

// iOS 7-9
%hook SBScreenShotter

- (void)saveScreenshot:(BOOL)screenshot {
	%orig;
	saveLatestPhotoToCurrentAppAlbum();
}

%end

static void saveLatestPhotoToCurrentAppAlbum() {
	NSString *displayName;
	SBApplication *frontMostApplication = [[UIApplication sharedApplication] _accessibilityFrontMostApplication];
	// Get active application name
	if(frontMostApplication) {
		displayName = [frontMostApplication displayName];
	}else {
		displayName = @"Other Screenshots";
	}
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, SAVE_DELAY * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
		moveLatestPhotoToAlbumWithName(displayName);
	});
}

static void saveLatestPHAssetToCollection(PHAssetCollection *collection, NSString *albumName) {
	// Get latest image
	PHFetchOptions *latestFetchOptions = [PHFetchOptions new];
	latestFetchOptions.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:YES]];
	PHFetchResult *fetchResult = [PHAsset fetchAssetsWithMediaType:PHAssetMediaTypeImage options:latestFetchOptions];
	PHAsset *lastAsset = [fetchResult lastObject];
	// Save to the album
	HBLogDebug(@"Saving to album %@", albumName);
	[[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
		HBLogDebug(@"Getting photo asset");
	    PHFetchResult *photosAsset = [PHAsset fetchAssetsInAssetCollection:collection options:nil];
		HBLogDebug(@"Getting album change request %@", photosAsset);
	    PHAssetCollectionChangeRequest *albumChangeRequest = [PHAssetCollectionChangeRequest changeRequestForAssetCollection:collection assets:photosAsset];
		HBLogDebug(@"Adding asset %@", albumChangeRequest);
	    [albumChangeRequest addAssets:@[lastAsset]];
		HBLogDebug(@"Added asset");
	} completionHandler:^(BOOL success, NSError *error) {
	    if(success) {
	        HBLogDebug(@"Saved '%@'", albumName);
	    }else {
	        HBLogDebug(@"Error saving: %@", [error description]);
	    }
	}];
}

static void moveLatestPhotoToAlbumWithName(NSString *albumName) {

	// iOS 8-10
	HBLogDebug(@"Checking PHPhotoLibrary exists");
	if(%c(PHPhotoLibrary)) {

		__block PHAssetCollection *collection;
		__block PHObjectPlaceholder *placeholder;

		// Find the album
		HBLogDebug(@"Fetching options");
		PHFetchOptions *albumFetchOptions = [PHFetchOptions new];
		HBLogDebug(@"Getting predicate");
		albumFetchOptions.predicate = [NSPredicate predicateWithFormat:@"title = %@", albumName];
		HBLogDebug(@"Getting collection");
		collection = [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeAlbum subtype:PHAssetCollectionSubtypeAny options:albumFetchOptions].firstObject;
		// Create the album ifdoesn't exist
		if(!collection) {
    		[[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
        		PHAssetCollectionChangeRequest *createAlbum = [PHAssetCollectionChangeRequest creationRequestForAssetCollectionWithTitle:albumName];
        		placeholder = [createAlbum placeholderForCreatedAssetCollection];
    		} completionHandler:^(BOOL success, NSError *error) {
        		if(success) {
					HBLogDebug(@"Created album for '%@'", albumName);
					PHFetchResult *collectionFetchResult = [PHAssetCollection fetchAssetCollectionsWithLocalIdentifiers:@[placeholder.localIdentifier] options:nil];
            		collection = collectionFetchResult.firstObject;
					saveLatestPHAssetToCollection(collection, albumName);
        		}else {
					HBLogDebug(@"Error creating album: %@", [error description]);
				}
    		}];
		}else {
			saveLatestPHAssetToCollection(collection, albumName);
		}

	}
	// iOS 7
	else {
		HBLogDebug(@"Using ALAssetsLibrary");
		ALAssetsLibrary *library = [ALAssetsLibrary new];
		[library enumerateGroupsWithTypes:ALAssetsGroupSavedPhotos usingBlock:^(ALAssetsGroup *group, BOOL *stop) {
		    // Only enumerate photos
		    [group setAssetsFilter:[ALAssetsFilter allPhotos]];
			// Get last item (NSEnumerationReverse means last starting first, so first item then stop)
		    [group enumerateAssetsWithOptions:NSEnumerationReverse usingBlock:^(ALAsset *alAsset, NSUInteger index, BOOL *innerStop) {
		        if(alAsset) {
					*stop = YES;
					*innerStop = YES;
		            __block BOOL albumWasFound = NO;
					// Enumerate each existing album
    				[library enumerateGroupsWithTypes:ALAssetsGroupAlbum usingBlock:^(ALAssetsGroup *group, BOOL *stop) {
						// Found album
                        if([albumName isEqualToString:[group valueForProperty:ALAssetsGroupPropertyName]]) {
                            albumWasFound = YES;
                            [group addAsset:alAsset];
                            return;
						// Create album because doesn't exist
                        }else if(group == nil && !albumWasFound) {
                            [library addAssetsGroupAlbumWithName:albumName resultBlock:^(ALAssetsGroup *group) {
                                [group addAsset:alAsset];
                        	} failureBlock:nil];
                        }
                    } failureBlock:nil];
		        }
		    }];
		} failureBlock:nil];
	}

}
