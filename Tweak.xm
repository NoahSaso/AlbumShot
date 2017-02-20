@import AssetsLibrary;
@import Photos;
#include <stdarg.h>

// Delay save to album for SAVE_DELAY seconds so phone has time to add image to camera roll
#define SAVE_DELAY 3

static void saveLatestPhotoToCurrentAppAlbum();
static void moveLatestPhotoToAlbumWithName(NSString *albumName);
static void saveLatestPHAssetToCollection(PHAssetCollection *collection, NSString *albumName);

@interface SBApplication : NSObject
- (id)displayName;
@end

@interface UIApplication (AlbumShot)
- (id)_accessibilityFrontMostApplication;
@end

%group SpringBoard
// iOS 10
%hook SBScreenshotManager
- (void)saveScreenshotsWithCompletion:(id)arg1 {
	%orig; saveLatestPhotoToCurrentAppAlbum();
}
%end
// iOS 7-9
%hook SBScreenShotter
- (void)saveScreenshot:(BOOL)screenshot {
	%orig; saveLatestPhotoToCurrentAppAlbum();
}
%end
%end

%group Camera
// iOS 10
%hook CAMCaptureEngine
- (void)captureOutput:(id)arg1 didFinishCaptureForResolvedSettings:(id)arg2 error:(id)arg3 {
	%orig; saveLatestPhotoToCurrentAppAlbum();
}
%end
%end

%group Both
%end

static void saveLatestPhotoToCurrentAppAlbum() {
	dispatch_async(dispatch_get_main_queue(), ^{
		NSString *displayName;
		if([[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.apple.camera"]) {
			displayName = @"Camera";
		}else {
			SBApplication *frontMostApplication = [[UIApplication sharedApplication] _accessibilityFrontMostApplication];
			// Get active application name
			if(frontMostApplication) {
				displayName = [frontMostApplication displayName];
			}else {
				displayName = @"Other Screenshots";
			}
		}
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, SAVE_DELAY * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
			moveLatestPhotoToAlbumWithName(displayName);
		});
	});
}

static void saveLatestPHAssetToCollection(PHAssetCollection *collection, NSString *albumName) {
	// Get latest image
	PHFetchOptions *latestFetchOptions = [PHFetchOptions new];
	latestFetchOptions.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:YES]];
	PHFetchResult *fetchResult = [PHAsset fetchAssetsWithMediaType:PHAssetMediaTypeImage options:latestFetchOptions];
	PHAsset *lastAsset = [fetchResult lastObject];
	// Save to the album
	HBLogDebug(@"Saving asset to album '%@'", albumName);
	[[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
	    PHFetchResult *photosAsset = [PHAsset fetchAssetsInAssetCollection:collection options:nil];
	    PHAssetCollectionChangeRequest *albumChangeRequest = [PHAssetCollectionChangeRequest changeRequestForAssetCollection:collection assets:photosAsset];
	    [albumChangeRequest addAssets:@[lastAsset]];
	} completionHandler:^(BOOL success, NSError *error) {
	    if(success) {
	        HBLogDebug(@"Saved asset to album '%@'", albumName);
	    }else {
	        HBLogDebug(@"Error saving asset to album '%@': %@", albumName, [error description]);
	    }
	}];
}

static void moveLatestPhotoToAlbumWithName(NSString *albumName) {

	// iOS 8-10
	if(%c(PHPhotoLibrary)) {
		HBLogDebug(@"Using PHPhotoLibrary");

		__block PHAssetCollection *collection;
		__block PHObjectPlaceholder *placeholder;

		// Find the album
		PHFetchOptions *albumFetchOptions = [PHFetchOptions new];
		albumFetchOptions.predicate = [NSPredicate predicateWithFormat:@"title = %@", albumName];
		collection = [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeAlbum subtype:PHAssetCollectionSubtypeAny options:albumFetchOptions].firstObject;
		// Create the album ifdoesn't exist
		if(!collection) {
    		[[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
        		PHAssetCollectionChangeRequest *createAlbum = [PHAssetCollectionChangeRequest creationRequestForAssetCollectionWithTitle:albumName];
        		placeholder = [createAlbum placeholderForCreatedAssetCollection];
    		} completionHandler:^(BOOL success, NSError *error) {
        		if(success) {
					HBLogDebug(@"Created album named '%@'", albumName);
					PHFetchResult *collectionFetchResult = [PHAssetCollection fetchAssetCollectionsWithLocalIdentifiers:@[placeholder.localIdentifier] options:nil];
            		collection = collectionFetchResult.firstObject;
					saveLatestPHAssetToCollection(collection, albumName);
        		}else {
					HBLogDebug(@"Error creating album named '%@': %@", albumName, [error description]);
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
							HBLogDebug(@"Added asset to found album '%@'", albumName);
                            return;
						// Create album because doesn't exist
                        }else if(group == nil && !albumWasFound) {
							HBLogDebug(@"Creating album named '%@'", albumName);
                            [library addAssetsGroupAlbumWithName:albumName resultBlock:^(ALAssetsGroup *group) {
                                [group addAsset:alAsset];
								HBLogDebug(@"Added asset to album '%@'", albumName);
                        	} failureBlock:nil];
                        }
                    } failureBlock:nil];
		        }
		    }];
		} failureBlock:nil];
	}

}

%ctor {
	NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
	if([bundleID isEqualToString:@"com.apple.springboard"]) {
		%init(SpringBoard);
	}else if([bundleID isEqualToString:@"com.apple.camera"]) {
		%init(Camera);
	}
	%init(Both);
}
