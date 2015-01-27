#define log(z) NSLog(@"[AlbumShot] %@", z)
#define str(z, ...) [NSString stringWithFormat:z, ##__VA_ARGS__]

#import "ALAssetsLibrary+CustomPhotoAlbum.h"

// Get screenshot C method definition
extern "C" UIImage *_UICreateScreenUIImage();

@interface SBScreenFlash : NSObject
// iOS 7
+ (id)sharedInstance;
- (void)flash;
// iOS 8+
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
	if([%c(SBScreenFlash) respondsToSelector:@selector(sharedInstance)])
		return [self sharedInstance]; // iOS 7
	return [self mainScreenFlasher]; // iOS 8+
}

%new -(void)flashWhiteNow {
	if([self respondsToSelector:@selector(flash)])
		[self flash]; // iOS 7
	else
		[self flashWhiteWithCompletion:nil]; // iOS 8+
}

%end

%hook SBScreenShotter

- (void)saveScreenshot:(BOOL)screenshot {
	// Get front application
	SBApplication *frontMostApplication = [[UIApplication sharedApplication] _accessibilityFrontMostApplication];
	if(!frontMostApplication) { // No application open
		log(@"No app open");
		%orig;
		return;
	}
	// Get application name
	NSString *displayName = [frontMostApplication displayName];
	// Get screenshot
	UIImage *screenImage = _UICreateScreenUIImage();
	// Flash like normal
	[[%c(SBScreenFlash) mySharedInstance] flashWhiteNow];
	// Save to album
	ALAssetsLibrary *library = [[ALAssetsLibrary alloc] init];
	[library saveImage:screenImage toAlbum:displayName withCompletionBlock: ^(NSError *error) {
		if(error != nil) {
			log(str(@"Error saving: %@", [error description]));
		}else {
			log(str(@"Saved '%@'", displayName));
		}
	}];
}

%end
